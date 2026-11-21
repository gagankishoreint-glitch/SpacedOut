import AppKit
import Carbon.HIToolbox
import SpacedOutCore
import SwiftUI

struct ShortcutRecorderView: View {
    let currentBinding: HotkeyBinding
    let onCaptured: (HotkeyBinding) -> Bool
    let onResetDefault: () -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14
    ]

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(isRecording ? "Press shortcut… (Esc cancels)" : currentBinding.displayString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if currentBinding != .defaultToggleWidget {
                Button("Reset") {
                    stopRecording()
                    onResetDefault()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    @MainActor
    private func startRecording() {
        stopRecording()
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            let mods = GlobalHotkeyManager.hotkeyModifiers(from: event.modifierFlags)
            let isFunctionKey = Self.functionKeyCodes.contains(Int(event.keyCode))

            // don't steal plain typing unless it's an F-key
            guard !mods.isEmpty || isFunctionKey else {
                NSSound.beep()
                return nil
            }

            let label = GlobalHotkeyManager.label(
                for: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers
            )
            let binding = HotkeyBinding(
                keyCode: UInt32(event.keyCode),
                modifiers: mods,
                keyLabel: label
            )

            _ = onCaptured(binding)
            stopRecording()
            return nil
        }
    }

    @MainActor
    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
