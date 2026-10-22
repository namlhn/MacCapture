import AppKit
import SwiftUI

public struct AppLogoBadgeView: View {
    private let size: CGFloat

    public init(size: CGFloat = 28) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.39, blue: 0.92),
                                    Color(red: 0.49, green: 0.23, blue: 0.93),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: size * 0.52, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1)
    }
}

public struct ToolbarView: View {
    @ObservedObject private var viewModel: ToolbarViewModel
    @ObservedObject private var preferences: PreferencesStore
    private let onDragDelta: (CGSize) -> Void
    private let onDragEnded: () -> Void

    public init(
        viewModel: ToolbarViewModel,
        onDragDelta: @escaping (CGSize) -> Void = { _ in },
        onDragEnded: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.preferences = viewModel.preferences
        self.onDragDelta = onDragDelta
        self.onDragEnded = onDragEnded
    }

    public var body: some View {
        Group {
            if viewModel.isCollapsedToEdge {
                collapsedEdgeHandle
            } else {
                expandedBar
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FloatingToolbarRoot")
    }

    private var collapsedEdgeHandle: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                viewModel.isCollapsedToEdge = false
            }
        } label: {
            HStack(spacing: 3) {
                AppLogoBadgeView(size: 20)
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.primary.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .help("Expand MacCapture Toolbar")
        .accessibilityLabel("Expand MacCapture Toolbar")
    }

    private var expandedBar: some View {
        let size = preferences.toolbarScale.panelSize
        return HStack(spacing: 6) {
            brandDragHeader

            Divider()
                .frame(height: 22)
                .opacity(0.55)

            // Capture Modes Group
            HStack(spacing: 4) {
                toolbarCaptureButton(
                    mode: .region,
                    shortcut: viewModel.shortcutLabel(for: .captureRegion)
                )

                toolbarCaptureButton(
                    mode: .window,
                    shortcut: viewModel.shortcutLabel(for: .captureWindow)
                )

                fullscreenButton

                toolbarCaptureButton(
                    mode: .scrolling,
                    shortcut: viewModel.shortcutLabel(for: .captureScrolling)
                )
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Divider()
                .frame(height: 22)
                .opacity(0.55)

            delayMenu

            recordButton

            moreMenu

            hideButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: size.width, height: size.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.primary.opacity(0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
    }

    private var brandDragHeader: some View {
        HStack(spacing: 5) {
            AppLogoBadgeView(size: 28)

            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 2)
        .padding(.trailing, 3)
        .frame(height: 34)
        .contentShape(Rectangle())
        .help("MacCapture • Drag to move toolbar, double-click to reset position")
        .accessibilityLabel("MacCapture Logo and Drag Handle")
        .accessibilityHint("Drag to move toolbar or double-click to reset position")
        .onTapGesture(count: 2) {
            viewModel.resetPosition()
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    onDragDelta(value.translation)
                }
                .onEnded { _ in
                    onDragEnded()
                }
        )
    }

    private func toolbarCaptureButton(mode: CaptureMode, shortcut: String) -> some View {
        Button {
            viewModel.triggerCapture(mode)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(mode.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 36, minHeight: 30)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(ToolbarCapturePillStyle())
        .help("\(mode.displayName) Capture (\(shortcut))")
        .accessibilityLabel("\(mode.displayName) Capture")
        .accessibilityHint("Shortcut \(shortcut)")
        .accessibilityIdentifier("ToolbarButton_\(mode.rawValue)")
    }

    private var fullscreenButton: some View {
        let shortcut = viewModel.shortcutLabel(for: .captureFullscreen)
        return Group {
            if viewModel.availableDisplays.count > 1 {
                Menu {
                    ForEach(viewModel.availableDisplays) { display in
                        Button("Capture \(display.name) (\(display.pixelWidth)×\(display.pixelHeight))") {
                            viewModel.triggerCapture(.fullscreen, displayID: display.id)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: CaptureMode.fullscreen.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(CaptureMode.fullscreen.displayName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(minWidth: 36, minHeight: 30)
                } primaryAction: {
                    viewModel.triggerCapture(.fullscreen)
                }
                .menuStyle(.borderlessButton)
                .help("Fullscreen Capture (\(shortcut)) • Click arrow to pick display")
            } else {
                toolbarCaptureButton(mode: .fullscreen, shortcut: shortcut)
            }
        }
    }

    private var delayMenu: some View {
        let hasActiveDelay = preferences.captureDelay != .none
        return Menu {
            Picker("Capture Delay", selection: $preferences.captureDelay) {
                ForEach(CaptureDelay.allCases, id: \.self) { delay in
                    Text("Delay: \(delay.label)").tag(delay)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: hasActiveDelay ? "timer.circle.fill" : "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hasActiveDelay ? Color.orange : Color.secondary)
                Text(preferences.captureDelay.label)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(hasActiveDelay ? Color.orange : Color.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hasActiveDelay ? Color.orange.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .frame(minWidth: 38, minHeight: 30)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Capture Delay (\(preferences.captureDelay.label))")
        .accessibilityLabel("Capture Delay \(preferences.captureDelay.label)")
        .accessibilityIdentifier("ToolbarMenu_Delay")
    }

    private var recordButton: some View {
        Group {
            if viewModel.isRecording {
                Button {
                    viewModel.triggerRecording(.fullscreen)
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 30)
                }
                .buttonStyle(ToolbarCapturePillStyle())
                .help("Stop Recording")
                .accessibilityLabel("Stop Recording")
            } else {
                Menu {
                    Button(RecordingMode.region.displayName) {
                        viewModel.triggerRecording(.region)
                    }
                    Button(RecordingMode.fullscreen.displayName) {
                        viewModel.triggerRecording(.fullscreen)
                    }
                } label: {
                    Image(systemName: "record.circle")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.red)
                        .frame(width: 28, height: 30)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Screen Recording (Region / Fullscreen)")
                .accessibilityLabel("Screen Recording")
            }
        }
        .accessibilityIdentifier("ToolbarMenu_Record")
    }

    private var moreMenu: some View {
        Menu {
            Button("Open Editor…") {
                viewModel.onOpenEditorRequested?()
            }
            Button("Reset Toolbar Position") {
                viewModel.resetPosition()
            }
            Divider()
            Button("Scrolling Capture") {
                viewModel.triggerCapture(.scrolling)
            }
            if viewModel.isRecording {
                Button("Stop Recording") {
                    viewModel.triggerRecording(.fullscreen)
                }
            } else {
                Button(RecordingMode.region.displayName) {
                    viewModel.triggerRecording(.region)
                }
                Button(RecordingMode.fullscreen.displayName) {
                    viewModel.triggerRecording(.fullscreen)
                }
            }
            Divider()
            Button("Preferences…") {
                viewModel.onOpenPreferencesRequested?()
            }
            Button("Hide Toolbar") {
                viewModel.hideToolbar()
            }
            Divider()
            Button("Quit MacCapture") {
                viewModel.onQuitRequested?()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13.5, weight: .medium))
                .frame(width: 28, height: 30)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More Actions")
        .accessibilityLabel("More Actions")
        .accessibilityIdentifier("ToolbarMenu_More")
    }

    private var hideButton: some View {
        Button {
            viewModel.hideToolbar()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ToolbarCapturePillStyle())
        .help("Hide Floating Toolbar (App stays in Menu Bar)")
        .accessibilityLabel("Hide Floating Toolbar")
        .accessibilityIdentifier("ToolbarButton_Hide")
    }
}

private struct ToolbarCapturePillStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.accentColor.opacity(0.22)
                            : (isHovering ? Color.primary.opacity(0.10) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isHovering ? Color.accentColor.opacity(0.32) : Color.clear,
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
