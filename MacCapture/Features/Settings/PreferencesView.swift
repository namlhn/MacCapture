import Carbon
import SwiftUI

public struct PreferencesView: View {
    @ObservedObject private var preferences: PreferencesStore
    private let onResetToolbarPosition: () -> Void
    private let onOpenScreenPermissions: () -> Void

    public init(
        preferences: PreferencesStore,
        onResetToolbarPosition: @escaping () -> Void = {},
        onOpenScreenPermissions: @escaping () -> Void = {}
    ) {
        self.preferences = preferences
        self.onResetToolbarPosition = onResetToolbarPosition
        self.onOpenScreenPermissions = onOpenScreenPermissions
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }

            privacyTab
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .padding(18)
        .frame(width: 480, height: 340)
    }

    private var generalTab: some View {
        Form {
            Section("Floating Toolbar") {
                Toggle("Show floating toolbar on launch", isOn: $preferences.showToolbarOnStartup)
                Toggle("Keep toolbar always on top", isOn: $preferences.alwaysOnTop)
                Toggle("Show toolbar across all Spaces", isOn: $preferences.showOnAllSpaces)
                Toggle("Auto-collapse toolbar near screen edge", isOn: $preferences.autoHideToEdge)

                Picker("Appearance", selection: $preferences.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.title).tag(theme)
                    }
                }

                Picker("Toolbar Size", selection: $preferences.toolbarScale) {
                    ForEach(ToolbarScale.allCases, id: \.self) { scale in
                        Text(scale.title).tag(scale)
                    }
                }

                HStack {
                    Spacer()
                    Button("Reset Toolbar Position") {
                        onResetToolbarPosition()
                    }
                }
            }

            Section("Screen Recording Audio") {
                Toggle("Record system audio (computer sound)", isOn: $preferences.recordSystemAudio)
                Toggle("Record microphone voice", isOn: $preferences.recordMicrophone)
            }

            Section("Startup") {
                Toggle("Launch MacCapture at login", isOn: $preferences.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Keyboard Shortcuts")
                .font(.headline)

            ForEach(HotkeyAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    shortcutPicker(for: action)
                }
            }

            let conflicts = preferences.hotkeyConflicts
            if !conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
                        Label(
                            "\(conflict.action.title) (\(conflict.shortcut.displayString)): \(conflict.reason)",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    preferences.resetHotkeysToDefault()
                }
            }
        }
        .padding(8)
    }

    private func shortcutPicker(for action: HotkeyAction) -> some View {
        let current = preferences.hotkeys[action] ?? .defaultRegion
        let presets: [HotkeyShortcut] = [
            .defaultRegion,
            .defaultWindow,
            .defaultFullscreen,
            .defaultScrolling,
            .defaultToggleToolbar,
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: UInt32(controlKey | optionKey), keyEquivalent: "4"),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_5), carbonModifiers: UInt32(controlKey | optionKey), keyEquivalent: "5"),
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_6), carbonModifiers: UInt32(controlKey | optionKey), keyEquivalent: "6"),
        ]

        return Menu(current.displayString) {
            ForEach(presets, id: \.self) { preset in
                Button(preset.displayString) {
                    preferences.hotkeys[action] = preset
                }
            }
        }
        .frame(width: 110)
    }

    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("100% Offline & Local", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("MacCapture processes all screenshots locally in memory. No images, analytics, or telemetry are ever uploaded to any server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Text("Screen Recording Permission")
                .font(.headline)

            Text("macOS requires Screen Recording permission so MacCapture can capture displays and individual windows using ScreenCaptureKit.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open System Settings → Screen Recording…") {
                onOpenScreenPermissions()
            }

            Spacer()
        }
        .padding(8)
    }
}
