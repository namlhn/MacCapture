import AppKit
import Foundation

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    public var isToolbarVisibleProvider: (() -> Bool)?
    public var onCaptureModeSelected: ((CaptureMode) -> Void)?
    public var onOpenEditorSelected: (() -> Void)?
    public var onToggleToolbarSelected: (() -> Void)?
    public var onOpenPreferencesSelected: (() -> Void)?
    public var onShowAboutSelected: (() -> Void)?
    public var onQuitSelected: (() -> Void)?

    private var toggleToolbarItem: NSMenuItem?

    override public init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "MacCapture"
            )
            button.toolTip = "MacCapture — Screen Capture & Annotation"
        }

        configureMenu()
        statusItem.menu = menu
    }

    public func refreshMenuLabels() {
        let visible = isToolbarVisibleProvider?() ?? true
        toggleToolbarItem?.title = visible ? "Hide Floating Toolbar" : "Show Floating Toolbar"
    }

    public func menuWillOpen(_ menu: NSMenu) {
        refreshMenuLabels()
    }

    private func configureMenu() {
        menu.delegate = self

        let regionItem = NSMenuItem(
            title: "Capture Region",
            action: #selector(captureRegionClicked),
            keyEquivalent: "1"
        )
        regionItem.keyEquivalentModifierMask = [.control, .command]
        regionItem.target = self
        menu.addItem(regionItem)

        let windowItem = NSMenuItem(
            title: "Capture Window",
            action: #selector(captureWindowClicked),
            keyEquivalent: "2"
        )
        windowItem.keyEquivalentModifierMask = [.control, .command]
        windowItem.target = self
        menu.addItem(windowItem)

        let fullscreenItem = NSMenuItem(
            title: "Capture Fullscreen",
            action: #selector(captureFullscreenClicked),
            keyEquivalent: "3"
        )
        fullscreenItem.keyEquivalentModifierMask = [.control, .command]
        fullscreenItem.target = self
        menu.addItem(fullscreenItem)

        let scrollingItem = NSMenuItem(
            title: "Capture Scrolling",
            action: #selector(captureScrollingClicked),
            keyEquivalent: "4"
        )
        scrollingItem.keyEquivalentModifierMask = [.control, .command]
        scrollingItem.target = self
        menu.addItem(scrollingItem)

        let openEditorItem = NSMenuItem(
            title: "Open Editor…",
            action: #selector(openEditorClicked),
            keyEquivalent: "o"
        )
        openEditorItem.keyEquivalentModifierMask = [.command]
        openEditorItem.target = self
        menu.addItem(openEditorItem)

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: "Hide Floating Toolbar",
            action: #selector(toggleToolbarClicked),
            keyEquivalent: "t"
        )
        toggleItem.keyEquivalentModifierMask = [.control, .command]
        toggleItem.target = self
        self.toggleToolbarItem = toggleItem
        menu.addItem(toggleItem)

        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(preferencesClicked),
            keyEquivalent: ","
        )
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let aboutItem = NSMenuItem(
            title: "About MacCapture",
            action: #selector(aboutClicked),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MacCapture",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func captureRegionClicked() {
        onCaptureModeSelected?(.region)
    }

    @objc private func captureWindowClicked() {
        onCaptureModeSelected?(.window)
    }

    @objc private func captureFullscreenClicked() {
        onCaptureModeSelected?(.fullscreen)
    }

    @objc private func captureScrollingClicked() {
        onCaptureModeSelected?(.scrolling)
    }

    @objc private func openEditorClicked() {
        onOpenEditorSelected?()
    }

    @objc private func toggleToolbarClicked() {
        onToggleToolbarSelected?()
        refreshMenuLabels()
    }

    @objc private func preferencesClicked() {
        onOpenPreferencesSelected?()
    }

    @objc private func aboutClicked() {
        onShowAboutSelected?()
    }

    @objc private func quitClicked() {
        onQuitSelected?()
    }
}
