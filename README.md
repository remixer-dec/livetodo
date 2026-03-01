# LiveTodo

A fork of tiny menu bar todo app for macOS. No Electron, no Xcode project, no dependencies — just a single Swift file compiled from the terminal.
The fork features todo item time tracking.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

## Features

- Lives in your menu bar — no Dock icon, no window clutter
- Add tasks with `Enter`, check them off with a click
- Double-click to edit, hover to reveal delete
- Archive completed lists to timestamped JSON files
- Data persisted locally in `~/Library/Application Support/LiveTodo/`
- Native macOS look and feel (SwiftUI + AppKit)
- ~600 lines of Swift. That's it.

## Install

### Build from source

```bash
git clone https://github.com/remixer-dec/livetodo.git
cd livetodo
chmod +x build.sh
./build.sh
```

Then either:

```bash
# Run directly
open LiveTodo.app

# Or copy to Applications
cp -r LiveTodo.app /Applications/
```

### Requirements

- macOS 14.0 or later
- Apple Silicon (arm64)
- Xcode Command Line Tools (`xcode-select --install`)

## Usage

| Action | How |
|---|---|
| Add a task | Type in the field, press `Enter` |
| Complete a task | Click the circle |
| Edit a task | Double-click the text |
| Delete a task | Hover, click `×` |
| Archive all | Click the **Archive** button |
| Start working on a task | Hover, click `play` |
| Move to next task | Click on `next` or `done`. |
| Quit | Right-click the menu bar icon → Quit |

## How it works

The entire app is a single `main.swift` file:

- **SwiftUI** for the popover UI
- **AppKit** (`NSStatusItem` + `NSPopover`) for menu bar integration
- **JSON files** in Application Support for persistence
- Compiled with `swiftc` — no Xcode project needed

## Project structure

```
livetodo/
├── main.swift      # The entire app
├── build.sh        # Build script
├── Info.plist      # App bundle metadata
├── LICENSE         # MIT
└── README.md
```

## Launch at login

To start LiveTodo automatically:

1. Open **System Settings** → **General** → **Login Items**
2. Click **+** and select `LiveTodo.app`

## License

MIT — see [LICENSE](LICENSE).

## Author

**Pierre-Baptiste Borges** — [@Liftof](https://github.com/Liftof)
