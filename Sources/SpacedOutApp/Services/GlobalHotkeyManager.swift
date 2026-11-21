import AppKit
import Carbon.HIToolbox
import Foundation
import SpacedOutCore

@MainActor
final class GlobalHotkeyManager {
    private final class RefsBox {
        var hotKeyRef: EventHotKeyRef?
        var eventHandlerRef: EventHandlerRef?

        deinit {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
        }
    }

    private let refs = RefsBox()
    private var currentHotKeyID: UInt32 = 0
    private var onTrigger: (() -> Void)?

    private static let signature: OSType = 0x53504F44 // "SPOD"

    func shutdown() {
        unregister()
        if let handler = refs.eventHandlerRef {
            RemoveEventHandler(handler)
            refs.eventHandlerRef = nil
        }
    }

    @discardableResult
    func register(binding: HotkeyBinding, action: @escaping @MainActor () -> Void) -> Bool {
        self.onTrigger = action
        installHandlerIfNeeded()

        var nextHotKeyRef: EventHotKeyRef?
        let nextID = currentHotKeyID &+ 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)

        let status = RegisterEventHotKey(
            binding.keyCode,
            Self.carbonModifiers(from: binding.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &nextHotKeyRef
        )

        guard status == noErr, let nextHotKeyRef else {
            return false
        }

        if let existing = refs.hotKeyRef {
            UnregisterEventHotKey(existing)
        }
        refs.hotKeyRef = nextHotKeyRef
        currentHotKeyID = nextID
        return true
    }

    func unregister() {
        if let hotKeyRef = refs.hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            refs.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard refs.eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData, let event else {
                return OSStatus(eventNotHandledErr)
            }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == GlobalHotkeyManager.signature else {
                return OSStatus(eventNotHandledErr)
            }

            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let firedID = hotKeyID.id
            DispatchQueue.main.async {
                manager.handleHotKey(id: firedID)
            }
            return noErr
        }

        var installedRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedRef
        )

        if status == noErr {
            refs.eventHandlerRef = installedRef
        }
    }

    private func handleHotKey(id: UInt32) {
        guard id == currentHotKeyID else { return }
        onTrigger?()
    }

    nonisolated static func carbonModifiers(from modifiers: HotkeyModifiers) -> UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }

    nonisolated static func hotkeyModifiers(from flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        var result: HotkeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option)  { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift)   { result.insert(.shift) }
        return result
    }

    nonisolated static func label(for keyCode: UInt16, charactersIgnoringModifiers: String?) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Fwd Del"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let chars = charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chars.isEmpty {
                return chars.uppercased()
            }
            return "Key \(keyCode)"
        }
    }
}
