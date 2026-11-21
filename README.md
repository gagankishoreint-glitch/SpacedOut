# SpacedOut

A native macOS 14+ desktop reminder and micro-task timer crafted for easily distracted minds. Built in Swift & SwiftUI (`SpacedOutCore` + `SpacedOutApp`) with a tactile frosted-glass UI, zero-drift wall-clock timers, unmissable multi-display full-screen alerts, and optional Apple Reminders sync.

## Features

- **Always-Reachable Floating Widget & Menu Bar Mode**
  - Switch seamlessly between **Widget & Menu Bar**, **Menu Bar Only**, and **Floating Widget Only**.
  - Drag anywhere on the widget glass surface to reposition; screen-parameter aware so disconnecting external monitors never strands the widget off-screen.
  - Zero-permission system-wide global shortcut (`⌥ Space` by default, customizable in Settings) via Carbon `RegisterEventHotKey`.
- **Instant Capture + Natural Quick Input**
  - **One-click presets** (`5m`, `10m`, `15m`, `25m` — customizable in Settings).
  - **Tactile Rotary Dial** (`1–99m`) with radial tick detents and trackpad haptic feedback.
  - **Smart Quick Input**:
    - `"tea 4m"` or `"15min stretch"` -> countdown timer
    - `"1h30m deep work"` -> compound duration (no 99-minute cap)
    - `"call Sam at 4:30pm"` or `"16:45 standup"` -> wall-clock scheduled reminder (rolls cleanly to next day if passed)
    - `"25"` -> quick 25-minute timer
- **Editable Running Timers**
  - Click a title inline to rename, hover for `-1m`, `+1m`, `+5m`, `Pause/Resume`, `Complete`, or `Delete`.
- **Full-Screen Multi-Display Notifications + Presentation Safe Mode**
  - Frosted full-screen takeover across all connected displays when time expires, with synthesized procedural audio chimes (`AVAudioEngine`) and Force Touch haptics.
  - Optional **30-second Pre-Alert** inside the widget before taking over the screen.
  - Instant keyboard triage on full-screen alerts: `Space` / `Return` (Complete), `1`–`4` (Snooze `+1m` / `+5m` / `+10m` / `+15m`), `Esc` (Dismiss).
  - **Presentation / Call Safe Mode** toggle in the widget header and menu bar downgrades full-screen overlays to native macOS banners during screen sharing.
- **Task History & `.ics` Export**
  - Searchable day-grouped timeline with daily focus stats (`Completed Today`, `Focus Minutes`, `On-Time Rate`), one-click **Run Again**, and RFC 5545 `.ics` export.
- **Apple Reminders Sync (Optional)**
  - Uses EventKit (`EKEventStore`) full access when enabled so reminders sync with iPhone, iPad, and Apple Watch with exact alarm timestamps.

## Architecture

```text
Sources/
├── SpacedOutCore/          # Pure Foundation domain engine (zero AppKit/SwiftUI coupling)
│   ├── Models.swift        # ReminderItem, HistoryEntry, AppSettings (forward-safe Codable)
│   ├── QuickInputParser.swift
│   ├── Persistence.swift   # Crash-safe atomic JSON store with corrupt backup preservation
│   ├── ICSExporter.swift   # RFC 5545 calendar export
│   └── TimerEngine.swift   # @Observable wall-clock engine (sleep/wake drift-proof)
└── SpacedOutApp/           # Native macOS 14+ AppKit + SwiftUI layer
    ├── Design/             # Tactile Frosted Glass tokens & NSVisualEffectView wrapper
    ├── Services/           # EventKit, Carbon Global Hotkeys, AVAudioEngine Chimes, UNNotifications, SMAppService
    ├── Windows/            # Non-activating NSPanel, Multi-screen Alert Overlay, NSStatusItem, Utility Windows
    └── Views/              # FloatingWidget, TactileDial, ReminderRow, FullScreenAlert, History, Settings
```

## Building & Running on macOS

Requires **macOS 14.0+** and **Xcode 15.3+** (or Xcode 16+ / Swift 5.10+).

### 1. Run unit tests
```bash
swift test
```

### 2. Build a signed `.app` bundle and launch
```bash
make run
```
This runs `swift test`, compiles a release build, assembles `dist/SpacedOut.app` with `Info.plist`, `AppIcon.icns`, and entitlements, ad-hoc signs it, and opens it.

### 3. Open in Xcode
- **Direct SwiftPM open:** `open Package.swift`
- **Or generate a full `.xcodeproj` with XcodeGen** (`brew install xcodegen`):
  ```bash
  make xcode
  ```

## Data Storage

Local state is saved atomically to `~/Library/Application Support/SpacedOut/state.json` (or inside the app's sandboxed container when sandbox-signed).
