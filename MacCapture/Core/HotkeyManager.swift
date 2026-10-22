import AppKit
import Carbon
import Foundation

public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case captureRegion
    case captureWindow
    case captureFullscreen
    case captureScrolling
    case toggleToolbar

    public var title: String {
        switch self {
        case .captureRegion: return "Capture Region"
        case .captureWindow: return "Capture Window"
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureScrolling: return "Capture Scrolling"
        case .toggleToolbar: return "Show/Hide Toolbar"
        }
    }
}

public struct HotkeyShortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var keyEquivalent: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyEquivalent: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyEquivalent = keyEquivalent
    }

    public static let defaultRegion = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_1),
        carbonModifiers: UInt32(controlKey | cmdKey),
        keyEquivalent: "1"
    )

    public static let defaultWindow = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_2),
        carbonModifiers: UInt32(controlKey | cmdKey),
        keyEquivalent: "2"
    )

    public static let defaultFullscreen = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_3),
        carbonModifiers: UInt32(controlKey | cmdKey),
        keyEquivalent: "3"
    )

    public static let defaultScrolling = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_4),
        carbonModifiers: UInt32(controlKey | cmdKey),
        keyEquivalent: "4"
    )

    public static let defaultToggleToolbar = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_T),
        carbonModifiers: UInt32(controlKey | cmdKey),
        keyEquivalent: "T"
    )

    public var displayString: String {
        var result = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { result += "⌃" }
        if (carbonModifiers & UInt32(optionKey)) != 0 { result += "⌥" }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { result += "⇧" }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { result += "⌘" }
        result += keyEquivalent.uppercased()
        return result
    }

    public var eventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbonModifiers & UInt32(controlKey)) != 0 { flags.insert(.control) }
        if (carbonModifiers & UInt32(optionKey)) != 0 { flags.insert(.option) }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { flags.insert(.shift) }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { flags.insert(.command) }
        return flags
    }
}

public struct HotkeyConflict: Equatable, Sendable {
    public let action: HotkeyAction
    public let shortcut: HotkeyShortcut
    public let reason: String

    public init(action: HotkeyAction, shortcut: HotkeyShortcut, reason: String) {
        self.action = action
        self.shortcut = shortcut
        self.reason = reason
    }
}

@MainActor
public final class HotkeyManager {
    private var registeredHotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var idToAction: [UInt32: HotkeyAction] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var bindings: [HotkeyAction: HotkeyShortcut] = [:]
    public var onActionTriggered: ((HotkeyAction) -> Void)?

    private static let signature: OSType = 0x4D43_4150 // 'MCAP'
    private weak static var activeInstance: HotkeyManager?

    public init() {
        Self.activeInstance = self
        installCarbonEventHandlerIfNeeded()
    }

    public func updateBindings(_ newBindings: [HotkeyAction: HotkeyShortcut]) {
        unregisterAll()
        bindings = newBindings

        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let shortcut = newBindings[action] else { continue }
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registeredHotKeyRefs[action] = ref
                idToAction[hotKeyID.id] = action
            }
        }
    }

    public func unregisterAll() {
        for (_, ref) in registeredHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeyRefs.removeAll()
        idToAction.removeAll()
    }

    public nonisolated static func validateConflicts(
        in bindings: [HotkeyAction: HotkeyShortcut]
    ) -> [HotkeyConflict] {
        var conflicts: [HotkeyConflict] = []
        var seen: [HotkeyShortcut: HotkeyAction] = [:]

        let systemReserved: [(UInt32, UInt32, String)] = [
            (UInt32(kVK_ANSI_3), UInt32(cmdKey | shiftKey), "macOS System Screenshot (⇧⌘3)"),
            (UInt32(kVK_ANSI_4), UInt32(cmdKey | shiftKey), "macOS System Region Screenshot (⇧⌘4)"),
            (UInt32(kVK_ANSI_5), UInt32(cmdKey | shiftKey), "macOS Screenshot Overlay (⇧⌘5)"),
            (UInt32(kVK_ANSI_Q), UInt32(cmdKey), "Quit Application (⌘Q)"),
        ]

        for action in HotkeyAction.allCases {
            guard let shortcut = bindings[action] else { continue }
            if let existingAction = seen[shortcut] {
                conflicts.append(
                    HotkeyConflict(
                        action: action,
                        shortcut: shortcut,
                        reason: "Duplicates shortcut assigned to \(existingAction.title)."
                    )
                )
            } else {
                seen[shortcut] = action
            }

            for (sysKey, sysMods, sysName) in systemReserved {
                if shortcut.keyCode == sysKey && shortcut.carbonModifiers == sysMods {
                    conflicts.append(
                        HotkeyConflict(
                            action: action,
                            shortcut: shortcut,
                            reason: "Conflicts with \(sysName)."
                        )
                    )
                }
            }
        }
        return conflicts
    }

    private func installCarbonEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
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
            guard status == noErr, hotKeyID.signature == HotkeyManager.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let pressedID = hotKeyID.id
            Task { @MainActor in
                HotkeyManager.activeInstance?.handlePressedHotKey(id: pressedID)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func handlePressedHotKey(id: UInt32) {
        guard let action = idToAction[id] else { return }
        onActionTriggered?(action)
    }
}
