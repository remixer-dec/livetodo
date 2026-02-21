// LittleTodo — A minimal menu bar todo app for macOS
// Copyright (c) 2025 Pierre-Baptiste Borges
// Licensed under the MIT License. See LICENSE for details.

import AppKit
import SwiftUI

// MARK: - Model

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool
    let createdAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.isDone = false
        self.createdAt = Date()
    }
}

// MARK: - Store

/// Manages todo items with JSON persistence in Application Support.
class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = []

    private let storageDir: URL
    private var todosURL: URL { storageDir.appendingPathComponent("todos.json") }
    private var archivesDir: URL { storageDir.appendingPathComponent("archives") }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("LittleTodo")
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: archivesDir, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: todosURL),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        self.items = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: todosURL, options: .atomic)
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(TodoItem(text: trimmed), at: 0)
        save()
    }

    func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isDone.toggle()
        save()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func update(_ item: TodoItem, newText: String) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].text = newText
        save()
    }

    /// Archives all current items to a timestamped JSON file and clears the list.
    func archiveAll() {
        guard !items.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "archive_\(formatter.string(from: Date())).json"
        let archiveFile = archivesDir.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: archiveFile, options: .atomic)
        }
        items.removeAll()
        save()
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
        .frame(width: 280)
    }

    private var divider: some View {
        Divider().opacity(0.5)
    }

    // MARK: Header

    private var headerView: some View {
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
                Button(action: {
                    withAnimation(.easeOut(duration: 0.25)) { store.archiveAll() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 10))
                        Text("Archive")
                            .font(.system(size: 11, weight: .medium))
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
        .padding(.bottom, 10)
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
            let done = store.items.filter { $0.isDone }.count
            Text("\(remaining) remaining")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
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
    @State private var editText: String
    @State private var isHovered = false

    init(item: TodoItem, store: TodoStore) {
        self.item = item
        self.store = store
        _editText = State(initialValue: item.text)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { store.toggle(item) }
            }) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(item.isDone ? .green : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        store.update(item, newText: editText)
                        isEditing = false
                    }
                    .onExitCommand {
                        editText = item.text
                        isEditing = false
                    }
            } else {
                Text(item.text)
                    .font(.system(size: 13))
                    .strikethrough(item.isDone, color: .secondary)
                    .foregroundColor(item.isDone ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        editText = item.text
                        isEditing = true
                    }
            }

            if isHovered || isEditing {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) { store.delete(item) }
                }) {
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
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
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

/// Manages the menu bar icon and popover window.
class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover

    init(store: TodoStore) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        let hostingController = NSHostingController(rootView: ContentView(store: store))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo")
            button.image?.size = NSSize(width: 16, height: 16)
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let quitItem = NSMenuItem(title: "Quit LittleTodo", action: #selector(quit), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
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

    @objc func quit() {
        NSApp.terminate(nil)
    }
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
