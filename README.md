# SpacedOut

A native macOS 14+ desktop reminder and micro-task timer crafted for easily distracted minds. Built in Swift & SwiftUI (`SpacedOutCore` + `SpacedOutApp`) with a tactile frosted-glass UI, zero-drift wall-clock timers, calendar scheduling, unmissable multi-display full-screen alerts, restart-resilient watchdog recovery, and two-way Apple Reminders + Apple Calendar sync.

## Features

- **Always-Reachable Floating Widget & Menu Bar Mode**
  - Switch seamlessly between **Widget & Menu Bar**, **Menu Bar Only**, and **Floating Widget Only**.
  - Drag anywhere on the widget glass surface to reposition; screen-parameter aware so disconnecting external monitors never strands the widget off-screen.
  - Zero-permission system-wide global shortcut (`⌥ Space` by default, customizable in Settings) via Carbon `RegisterEventHotKey`.
- **Instant Capture, Calendar Picker & Natural Quick Input**
  - **One-click presets** (`5m`, `10m`, `15m`, `25m` — customizable in Settings).
  - **Tactile Rotary Dial** (`1–99m`) with radial tick detents and trackpad haptic feedback.
  - **Calendar Scheduling Popover**: Click the calendar button beside the quick-input box to pick any future date and time (with `+1h`, `Tonight 8pm`, `Tomorrow 9am` shortcuts).
  - **Smart Quick Input**:
    - `"tea 4m"` or `"15min stretch"` -> countdown timer
    - `"1h30m deep work"` -> compound duration
    - `"call Sam at 4:30pm"` or `"16:45 standup"` -> wall-clock scheduled reminder
    - `"dentist tomorrow 9am"`, `"demo nov 25 at 2:30pm"`, `"mon 8:15am sync"`, `"12/01 14:00 pay rent"` -> multi-day calendar reminder
    - `"25"` -> quick 25-minute timer
- **Full Inline & Popover Editing on Active Timers**
  - Click a title to rename inline, hover for `-1m`, `+1m`, `+5m`, `Pause/Resume`, `Complete`, or `Delete`, or click the **Edit (`pencil`)** button on any row to edit title, duration, calendar date/time, and accent color mid-countdown.
- **Full-Screen Multi-Display Notifications + Presentation Safe Mode**
  - Frosted full-screen takeover across all connected displays when time expires, with synthesized procedural audio chimes (`AVAudioEngine`) and Force Touch haptics.
  - Optional **30-second Pre-Alert** inside the widget before taking over the screen.
  - Instant keyboard triage on full-screen alerts: `Space` / `Return` (Complete), `1`–`4` (Snooze `+1m` / `+5m` / `+10m` / `+15m`), `Esc` (Dismiss).
  - **Presentation / Call Safe Mode** toggle in the widget header and menu bar downgrades full-screen overlays to native macOS banners during screen sharing.
- **Accountability Watchdog & Restart Recovery**
  - When timers are running inside the `.app` bundle, a lightweight user `LaunchAgent` (`com.spacedout.app.watchdog`) keeps SpacedOut alive across crashes, force-quits, and Mac restarts.
  - Timers that expire while your Mac is off immediately catch up into the overdue alert queue on startup instead of letting you off the hook, while leaving Delete/Edit controls available inside SpacedOut.
- **Task History, User Activity Log & `.ics` Export**
  - **Task History** tab with searchable day-grouped completions, focus stats, one-click **Run Again**, and RFC 5545 `.ics` export.
  - **Activity Log** tab recording every creation, edit, time adjustment, pause/resume, snooze, restart recovery, Apple sync change, watchdog event, and removal with search, category filters, and `.txt` export.
- **Two-Way Apple Reminders & Apple Calendar Sync (Enabled by Default)**
  - Uses EventKit (`EKEventStore`) full access for both Reminders (`EKReminder`) and Calendar events (`EKEvent`).
  - Edits, completions, and deletions made in Apple Reminders or Apple Calendar reconcile back into SpacedOut and appear in the Activity Log.

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
    ├── Services/           # EventKit (Reminders + Calendar), LaunchAgent Watchdog, Carbon Hotkeys, Audio, Notifications
    ├── Windows/            # Non-activating NSPanel, Multi-screen Alert Overlay, NSStatusItem, Utility Windows
    └── Views/              # FloatingWidget, TactileDial, ReminderRow, FullScreenAlert, History+Log, Settings
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

Local state (timers, history, activity log, and settings) is saved atomically to `~/Library/Application Support/SpacedOut/state.json`.
