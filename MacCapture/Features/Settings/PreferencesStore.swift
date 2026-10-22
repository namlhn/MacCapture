import AppKit
import Combine
import Foundation
import ServiceManagement

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    @MainActor
    public var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

public enum ToolbarScale: String, Codable, CaseIterable, Sendable {
    case compact
    case comfortable

    public var title: String {
        switch self {
        case .compact: return "Compact (476×48)"
        case .comfortable: return "Comfortable (508×52)"
        }
    }

    public var panelSize: CGSize {
        switch self {
        case .compact:
            return CGSize(width: 476, height: 48)
        case .comfortable:
            return CGSize(width: 508, height: 52)
        }
    }
}

@MainActor
public final class PreferencesStore: ObservableObject {
    private let defaults: UserDefaults

    private enum Keys {
        static let showToolbarOnStartup = "maccapture.showToolbarOnStartup"
        static let alwaysOnTop = "maccapture.alwaysOnTop"
        static let showOnAllSpaces = "maccapture.showOnAllSpaces"
        static let autoHideToEdge = "maccapture.autoHideToEdge"
        static let launchAtLogin = "maccapture.launchAtLogin"
        static let theme = "maccapture.theme"
        static let toolbarScale = "maccapture.toolbarScale"
        static let captureDelay = "maccapture.captureDelay"
        static let recordSystemAudio = "maccapture.recordSystemAudio"
        static let recordMicrophone = "maccapture.recordMicrophone"
        static let hotkeys = "maccapture.hotkeys"
    }

    @Published public var showToolbarOnStartup: Bool {
        didSet { defaults.set(showToolbarOnStartup, forKey: Keys.showToolbarOnStartup) }
    }

    @Published public var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }

    @Published public var showOnAllSpaces: Bool {
        didSet { defaults.set(showOnAllSpaces, forKey: Keys.showOnAllSpaces) }
    }

    @Published public var autoHideToEdge: Bool {
        didSet { defaults.set(autoHideToEdge, forKey: Keys.autoHideToEdge) }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            syncLaunchAtLogin()
        }
    }

    @Published public var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published public var toolbarScale: ToolbarScale {
        didSet { defaults.set(toolbarScale.rawValue, forKey: Keys.toolbarScale) }
    }

    @Published public var captureDelay: CaptureDelay {
        didSet { defaults.set(captureDelay.rawValue, forKey: Keys.captureDelay) }
    }

    @Published public var recordSystemAudio: Bool {
        didSet { defaults.set(recordSystemAudio, forKey: Keys.recordSystemAudio) }
    }

    @Published public var recordMicrophone: Bool {
        didSet { defaults.set(recordMicrophone, forKey: Keys.recordMicrophone) }
    }

    @Published public var hotkeys: [HotkeyAction: HotkeyShortcut] {
        didSet { saveHotkeys() }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.showToolbarOnStartup) == nil {
            defaults.set(true, forKey: Keys.showToolbarOnStartup)
        }
        if defaults.object(forKey: Keys.alwaysOnTop) == nil {
            defaults.set(true, forKey: Keys.alwaysOnTop)
        }
        if defaults.object(forKey: Keys.showOnAllSpaces) == nil {
            defaults.set(true, forKey: Keys.showOnAllSpaces)
        }
        if defaults.object(forKey: Keys.recordSystemAudio) == nil {
            defaults.set(true, forKey: Keys.recordSystemAudio)
        }
        if defaults.object(forKey: Keys.recordMicrophone) == nil {
            defaults.set(true, forKey: Keys.recordMicrophone)
        }

        self.showToolbarOnStartup = defaults.bool(forKey: Keys.showToolbarOnStartup)
        self.alwaysOnTop = defaults.bool(forKey: Keys.alwaysOnTop)
        self.showOnAllSpaces = defaults.bool(forKey: Keys.showOnAllSpaces)
        self.autoHideToEdge = defaults.bool(forKey: Keys.autoHideToEdge)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.recordSystemAudio = defaults.bool(forKey: Keys.recordSystemAudio)
        self.recordMicrophone = defaults.bool(forKey: Keys.recordMicrophone)

        if let rawTheme = defaults.string(forKey: Keys.theme),
           let parsedTheme = AppTheme(rawValue: rawTheme) {
            self.theme = parsedTheme
        } else {
            self.theme = .system
        }

        if let rawScale = defaults.string(forKey: Keys.toolbarScale),
           let parsedScale = ToolbarScale(rawValue: rawScale) {
            self.toolbarScale = parsedScale
        } else {
            self.toolbarScale = .compact
        }

        let rawDelay = defaults.integer(forKey: Keys.captureDelay)
        self.captureDelay = CaptureDelay(rawValue: rawDelay) ?? .none

        if let data = defaults.data(forKey: Keys.hotkeys),
           let decoded = try? JSONDecoder().decode([HotkeyAction: HotkeyShortcut].self, from: data) {
            self.hotkeys = decoded
        } else {
            self.hotkeys = Self.defaultHotkeys
        }
    }

    public static var defaultHotkeys: [HotkeyAction: HotkeyShortcut] {
        [
            .captureRegion: .defaultRegion,
            .captureWindow: .defaultWindow,
            .captureFullscreen: .defaultFullscreen,
            .captureScrolling: .defaultScrolling,
            .toggleToolbar: .defaultToggleToolbar,
        ]
    }

    public func resetHotkeysToDefault() {
        hotkeys = Self.defaultHotkeys
    }

    public var hotkeyConflicts: [HotkeyConflict] {
        HotkeyManager.validateConflicts(in: hotkeys)
    }

    private func saveHotkeys() {
        if let data = try? JSONEncoder().encode(hotkeys) {
            defaults.set(data, forKey: Keys.hotkeys)
        }
    }

    private func syncLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            // In unsigned/local dev builds SMAppService may refuse registration; ignore gracefully.
        }
    }
}
