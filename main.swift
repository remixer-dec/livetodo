// LittleTodo — A minimal menu bar todo app for macOS
// Copyright (c) 2025 Pierre-Baptiste Borges
// time-tracker fork by remixer-dec
// Licensed under the MIT License. See LICENSE for details.

import AppKit
import Combine
import SwiftUI

// MARK: - Helpers

/// Formats a TimeInterval as MM:SS or H:MM:SS.
func formatTime(_ interval: TimeInterval) -> String {
    let total   = max(0, Int(interval))
    let hours   = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Model

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool
    let createdAt: Date
    /// Accumulated time for each completed "lap" of work on this item.
    var sectionTimes: [TimeInterval]

    init(text: String) {
        self.id           = UUID()
        self.text         = text
        self.isDone       = false
        self.createdAt    = Date()
        self.sectionTimes = []
    }

    // Custom decoder so existing JSON (without sectionTimes) keeps working.
    init(from decoder: Decoder) throws {
        let c          = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,   forKey: .id)
        text           = try c.decode(String.self, forKey: .text)
        isDone         = try c.decode(Bool.self,   forKey: .isDone)
        createdAt      = try c.decode(Date.self,   forKey: .createdAt)
        sectionTimes   = try c.decodeIfPresent([TimeInterval].self, forKey: .sectionTimes) ?? []
    }

    /// Total time recorded across all laps for this item.
    var totalTime: TimeInterval { sectionTimes.reduce(0, +) }
}

// MARK: - Store

/// Manages todo items with JSON persistence and a live section timer.
class TodoStore: ObservableObject {

    // ── Persisted state ──────────────────────────────────────────────────────
    @Published var items: [TodoItem] = []

    // ── Timer state ──────────────────────────────────────────────────────────
    @Published var activeItemId:  UUID?         = nil
    @Published var currentElapsed: TimeInterval = 0   // seconds since section start

    private var sectionStartTime: Date? = nil
    private var ticker: Timer?          = nil

    // ── Persistence plumbing ─────────────────────────────────────────────────
    private let storageDir:  URL
    private var todosURL:    URL { storageDir.appendingPathComponent("todos.json") }
    private var archivesDir: URL { storageDir.appendingPathComponent("archives") }

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("LittleTodo")
        try? FileManager.default.createDirectory(at: storageDir,  withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: archivesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data    = try? Data(contentsOf: todosURL),
              let decoded = try? decoder.decode([TodoItem].self, from: data)
        else { return }
        self.items = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting    = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: todosURL, options: .atomic)
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Append to the end so sequential runs stay in order.
        items.append(TodoItem(text: trimmed))
        save()
    }

    func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isDone.toggle()
        save()
    }

    func delete(_ item: TodoItem) {
        if item.id == activeItemId { cancelTimer() }
        items.removeAll { $0.id == item.id }
        save()
    }

    func update(_ item: TodoItem, newText: String) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].text = newText
        save()
    }

    func archiveAll() {
        guard !items.isEmpty else { return }
        cancelTimer()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let file    = archivesDir.appendingPathComponent("archive_\(formatter.string(from: Date())).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting     = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) { try? data.write(to: file, options: .atomic) }
        items.removeAll()
        save()
    }

    // MARK: Section Timer

    /// Starts timing `item`.  Automatically saves the current lap if another item was running.
    func startTimer(for item: TodoItem) {
        guard !item.isDone else { return }
        // Save partial lap for the previous active item (if any).
        flushCurrentLap(markDone: false)

        activeItemId      = item.id
        sectionStartTime  = Date()
        currentElapsed    = 0

        if ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
        }
    }

    /// Records the current lap, marks the item done, and auto-advances to the next undone item.
    func nextSection() {
        guard let activeId = activeItemId,
              let idx = items.firstIndex(where: { $0.id == activeId }),
              let startTime = sectionStartTime
        else { return }

        items[idx].sectionTimes.append(Date().timeIntervalSince(startTime))
        items[idx].isDone = true
        save()

        // Find next undone item (first one after current in list order).
        if let nextIdx = items.indices.first(where: { $0 > idx && !items[$0].isDone }) {
            activeItemId     = items[nextIdx].id
            sectionStartTime = Date()
            currentElapsed   = 0
        } else {
            // All done — stop everything.
            activeItemId     = nil
            sectionStartTime = nil
            currentElapsed   = 0
            ticker?.invalidate()
            ticker = nil
            save()
        }
    }

    /// Pauses the timer, saving the current lap so it can be resumed later.
    func pauseTimer() {
        flushCurrentLap(markDone: false)
        save()
        activeItemId     = nil
        sectionStartTime = nil
        currentElapsed   = 0
        ticker?.invalidate()
        ticker = nil
    }

    /// Stops the timer without recording a lap or advancing.
    func cancelTimer() {
        activeItemId     = nil
        sectionStartTime = nil
        currentElapsed   = 0
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Derived

    var isTimerRunning: Bool { activeItemId != nil }

    /// Sum of all *recorded* section laps across every item.
    var totalRecordedTime: TimeInterval { items.reduce(0) { $0 + $1.totalTime } }

    /// Recorded + currently-running lap — what we show in the menu bar.
    var totalDisplayTime: TimeInterval { totalRecordedTime + currentElapsed }

    /// True when there is a next undone item after the active one.
    var hasNextSection: Bool {
        guard let activeId = activeItemId,
              let idx = items.firstIndex(where: { $0.id == activeId })
        else { return false }
        return items.indices.contains { $0 > idx && !items[$0].isDone }
    }

    // MARK: Private helpers

    private func tick() {
        guard let start = sectionStartTime else { return }
        currentElapsed = Date().timeIntervalSince(start)
    }

    /// Saves the running lap to the active item without marking it done.
    private func flushCurrentLap(markDone: Bool) {
        guard let activeId = activeItemId,
              let start = sectionStartTime,
              let idx = items.firstIndex(where: { $0.id == activeId })
        else { return }
        items[idx].sectionTimes.append(Date().timeIntervalSince(start))
        if markDone { items[idx].isDone = true }
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var store: TodoStore
    @State private var newText = ""

    var body: some View {
        VStack(spacing: 0) {
            headerView
            divider
            addFieldView
            divider

            if store.items.isEmpty {
                emptyState
            } else {
                itemsList
            }

            if !store.items.isEmpty {
                divider
                footerView
            }
        }
        .frame(width: 300)
    }

    private var divider: some View {
        Divider().opacity(0.5)
    }

    // MARK: Header

    private var headerView: some View {
        VStack(spacing: 0) {
            // Top row: title + archive button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("Todo")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                if !store.items.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { store.archiveAll() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "archivebox").font(.system(size: 10))
                            Text("Archive").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, store.isTimerRunning ? 6 : 10)

            // Active-session banner (only visible while timer runs)
            if store.isTimerRunning {
                activeBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isTimerRunning)
    }

    private var activeBanner: some View {
        HStack(spacing: 8) {
            // Pulsing red dot
            Circle()
                .fill(Color.red.opacity(0.85))
                .frame(width: 7, height: 7)

            // Current item name
            if let activeId = store.activeItemId,
               let item = store.items.first(where: { $0.id == activeId }) {
                Text(item.text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Current section elapsed time
            Text(formatTime(store.currentElapsed))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(.accentColor)

            // Next / Done button
            let isLast = !store.hasNextSection
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.nextSection() }
            } label: {
                HStack(spacing: 4) {
                    Text(isLast ? "Done" : "Next")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: isLast ? "checkmark" : "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isLast ? Color.green : Color.accentColor)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Add Field

    private var addFieldView: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.accentColor.opacity(0.8))
            TextField("Add a task...", text: $newText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    withAnimation(.easeOut(duration: 0.2)) { store.add(newText) }
                    newText = ""
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.3))
            Text("All clear")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: Items List

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    TodoRowView(item: item, store: store)
                    if index < store.items.count - 1 {
                        Divider().opacity(0.3).padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 320)
    }

    // MARK: Footer

    private var footerView: some View {
        HStack {
            let remaining = store.items.filter { !$0.isDone }.count
            let done      = store.items.filter {  $0.isDone }.count

            Text("\(remaining) remaining")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            // Show total time when there's something to show
            if store.totalDisplayTime > 0 {
                Text(formatTime(store.totalDisplayTime))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundColor(store.isTimerRunning ? .accentColor : .secondary)
            }

            if done > 0 {
                Text("\(done) done")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Todo Row

struct TodoRowView: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @State private var isEditing = false
    @State private var editText:  String
    @State private var isHovered = false

    init(item: TodoItem, store: TodoStore) {
        self.item  = item
        self.store = store
        _editText  = State(initialValue: item.text)
    }

    private var isActive: Bool { store.activeItemId == item.id }

    var body: some View {
        HStack(spacing: 10) {

            // ── Checkbox ──────────────────────────────────────────────────────
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { store.toggle(item) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(item.isDone ? .green : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)

            // ── Label / edit field ────────────────────────────────────────────
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit   { store.update(item, newText: editText); isEditing = false }
                    .onExitCommand { editText = item.text; isEditing = false }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.system(size: 13))
                        .strikethrough(item.isDone, color: .secondary)
                        .foregroundColor(item.isDone ? .secondary : .primary)
                        .lineLimit(2)
                        .help(item.text)

                    // Per-item elapsed time (shown when running or recorded)
                    let displayedTime = isActive
                        ? item.totalTime + store.currentElapsed
                        : item.totalTime
                    if displayedTime > 0 {
                        Text(formatTime(displayedTime))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundColor(isActive ? .accentColor : .secondary.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editText = item.text; isEditing = true }
            }

            // ── Run / active indicator ────────────────────────────────────────
            if !item.isDone {
                Button {
                    if isActive {
                        store.pauseTimer()
                    } else {
                        store.startTimer(for: item)
                    }
                } label: {
                    Image(systemName: isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isActive ? .accentColor : .secondary.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(isActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .opacity((isHovered || isActive) ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }

            // ── Delete button (hover/edit only) ───────────────────────────────
            if isHovered || isEditing {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.delete(item) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            isActive  ? Color.accentColor.opacity(0.07) :
            isHovered ? Color.primary.opacity(0.04)     : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .onChange(of: item.text) { _, newValue in
            if !isEditing { editText = newValue }
        }
    }
}

// MARK: - Status Bar Controller

/// Manages the menu-bar icon/clock and the popover window.
class StatusBarController: NSObject {
    private var statusItem:   NSStatusItem
    private var popover:      NSPopover
    private var cancellables: Set<AnyCancellable> = []

    init(store: TodoStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover    = NSPopover()
        super.init()

        popover.behavior = .transient
        let hc = NSHostingController(rootView: ContentView(store: store))
        hc.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hc

        // Initial button appearance
        applyIcon()

        if let button = statusItem.button {
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Observe every change to keep the menu-bar clock in sync.
        // We combine currentElapsed (ticks every second) + items (captures
        // completed-lap saves) so the display is always accurate.
        Publishers.CombineLatest(store.$currentElapsed, store.$items)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak store] _, _ in
                guard let store else { return }
                self?.updateMenuBarDisplay(store: store)
            }
            .store(in: &cancellables)
    }

    // MARK: Display helpers

    private func applyIcon() {
        guard let button = statusItem.button else { return }
        button.title = ""
        let img = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo")
        img?.size  = NSSize(width: 16, height: 16)
        button.image = img
    }

    private func updateMenuBarDisplay(store: TodoStore) {
        guard let button = statusItem.button else { return }
        let total = store.totalDisplayTime

        if total > 0 {
            // Show time as monospaced text; remove image to avoid overlap.
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: formatTime(total),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                ]
            )
        } else {
            // Nothing tracked yet — fall back to the checklist icon.
            button.attributedTitle = NSAttributedString(string: "")
            applyIcon()
        }
    }

    // MARK: Click handling

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let quit = NSMenuItem(title: "Quit LittleTodo",
                                  action: #selector(self.quit),
                                  keyEquivalent: "q")
            quit.target = self
            menu.addItem(quit)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    let store = TodoStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(store: store)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
