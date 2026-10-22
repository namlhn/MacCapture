import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var modeLabel: String = ""
    var onStop: (() -> Void)?

    var elapsedText: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            if !model.modeLabel.isEmpty {
                Text(model.modeLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(model.elapsedText)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
            Button {
                model.onStop?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityIdentifier("RecordingHUD_Stop")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
    }
}

/// Non-interactive border frame drawn around the active recording region.
private final class RecordingRegionBorderView: NSView {
    private let regionRectInView: CGRect
    private let pixelSizeText: String

    init(frame: CGRect, regionRectInView: CGRect, pixelSizeText: String) {
        self.regionRectInView = regionRectInView
        self.pixelSizeText = pixelSizeText
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Outer subtle dim outside the region so the recorded boundary stands out clearly
        ctx.saveGState()
        ctx.addRect(bounds)
        ctx.addRect(regionRectInView)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        ctx.drawPath(using: .eoFill)
        ctx.restoreGState()

        // Outer glow / border around the recorded area (drawn outside regionRectInView)
        let borderRect = regionRectInView.insetBy(dx: -2, dy: -2)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineDash(phase: 0, lengths: [8, 4])
        ctx.stroke(borderRect)
        ctx.restoreGState()

        // Corner L-brackets for crisp visual framing
        drawCornerBrackets(in: ctx, rect: regionRectInView.insetBy(dx: -3, dy: -3))

        // Top-left "REC • WxH" pill badge outside the region
        drawRecBadge(near: borderRect)
    }

    private func drawCornerBrackets(in ctx: CGContext, rect: CGRect) {
        let len: CGFloat = min(16, min(rect.width, rect.height) * 0.25)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(3.5)
        ctx.setLineCap(.round)

        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // bottom-left
            (CGPoint(x: rect.minX, y: rect.minY + len), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + len, y: rect.minY)),
            // bottom-right
            (CGPoint(x: rect.maxX - len, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + len)),
            // top-left
            (CGPoint(x: rect.minX, y: rect.maxY - len), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX + len, y: rect.maxY)),
            // top-right
            (CGPoint(x: rect.maxX - len, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY - len)),
        ]
        for (a, b, c) in corners {
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.addLine(to: c)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawRecBadge(near borderRect: CGRect) {
        let label = "● REC  \(pixelSizeText)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = label.size(withAttributes: attrs)
        let badgeW = textSize.width + 14
        let badgeH = textSize.height + 6

        let badgeX = min(max(borderRect.minX, bounds.minX + 6), bounds.maxX - badgeW - 6)
        let preferredTopY = borderRect.maxY + 6
        let badgeY = (preferredTopY + badgeH <= bounds.maxY - 4)
            ? preferredTopY
            : max(bounds.minY + 4, borderRect.minY - badgeH - 6)

        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        let path = NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5)
        NSColor.systemRed.withAlphaComponent(0.92).setFill()
        path.fill()
        label.draw(at: CGPoint(x: badgeRect.minX + 7, y: badgeRect.minY + 3), withAttributes: attrs)
    }
}

/// Orchestrates screen recording: permission, region selection, HUD, region frame overlay, saving.
@MainActor
public final class RecordingController {
    public enum State: Equatable { case idle, starting, recording }

    public private(set) var state: State = .idle {
        didSet { if oldValue != state { onStateChanged?(state) } }
    }

    public var onStateChanged: ((State) -> Void)?
    public var onHideAppChrome: (() -> Void)?
    public var onRestoreAppChrome: (() -> Void)?
    public var onPermissionDenied: ((RecordingMode) -> Void)?
    public var onRecordingSaved: ((URL) -> Void)?
    public var onError: ((Error) -> Void)?

    private let permissionManager: PermissionManaging
    private let captureEngine: CaptureEngineProtocol
    private let regionSelector: RegionSelecting
    private let recorder: ScreenRecording

    private var hudPanel: NSPanel?
    private var regionBorderWindow: NSWindow?
    private let hudModel = RecordingHUDModel()
    private var timer: Timer?
    private var startDate: Date?
    private var failureObserver: NSObjectProtocol?

    public var isActive: Bool { state != .idle }

    public init(
        permissionManager: PermissionManaging,
        captureEngine: CaptureEngineProtocol,
        regionSelector: RegionSelecting,
        recorder: ScreenRecording = ScreenRecorder()
    ) {
        self.permissionManager = permissionManager
        self.captureEngine = captureEngine
        self.regionSelector = regionSelector
        self.recorder = recorder
        hudModel.onStop = { [weak self] in
            Task { @MainActor in await self?.stopRecording() }
        }
    }

    public func toggle(mode: RecordingMode, delay: CaptureDelay = .none, preferredDisplayID: UInt32? = nil) async {
        if state == .recording {
            await stopRecording()
        } else {
            await startRecording(mode: mode, delay: delay, preferredDisplayID: preferredDisplayID)
        }
    }

    public func startRecording(mode: RecordingMode, delay: CaptureDelay = .none, preferredDisplayID: UInt32? = nil) async {
        guard state == .idle else { return }
        state = .starting

        var granted = permissionManager.currentStatus() == .granted
        if !granted { granted = await permissionManager.requestAccess() }
        guard granted else {
            state = .idle
            onPermissionDenied?(mode)
            return
        }

        if delay.rawValue > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay.rawValue) * 1_000_000_000)
        }

        onHideAppChrome?()
        try? await Task.sleep(nanoseconds: 35_000_000)

        do {
            let displays = try await captureEngine.listDisplays()
            let display: CaptureDisplay
            var region: CGRect?

            switch mode {
            case .region:
                let selection = try await regionSelector.selectRegion(displays: displays)
                guard let selected = displays.first(where: { $0.id == selection.displayID }) else {
                    throw CaptureError.displayNotFound(selection.displayID)
                }
                display = selected
                region = selection.rectInPixels
                // Let the selection overlay disappear before frames are recorded.
                regionSelector.cleanup()
                try? await Task.sleep(nanoseconds: 80_000_000)
            case .fullscreen:
                if let id = preferredDisplayID, let match = displays.first(where: { $0.id == id }) {
                    display = match
                } else if let primary = displays.first(where: { $0.isPrimary }) ?? displays.first {
                    display = primary
                } else {
                    throw CaptureError.noDisplaysAvailable
                }
            }

            // Show region frame & HUD BEFORE starting SCStream so MacCapture's windows are excluded from the video.
            if let region {
                showRegionBorder(on: display, regionInPixels: region)
            }
            showHUD(on: display, regionInPixels: region)
            try? await Task.sleep(nanoseconds: 100_000_000)

            try await recorder.start(
                displayID: display.id,
                regionInPixels: region,
                scaleFactor: display.scaleFactor,
                outputURL: Self.makeOutputURL()
            )
            startTimer()
            observeFailures()
            state = .recording
        } catch {
            regionSelector.cleanup()
            hideRegionBorder()
            hideHUD()
            onRestoreAppChrome?()
            state = .idle
            if let captureError = error as? CaptureError, captureError == .cancelled { return }
            onError?(error)
        }
    }

    public func stopRecording() async {
        guard state == .recording else { return }
        stopTimer()
        removeFailureObserver()
        hideRegionBorder()
        hideHUD()
        do {
            let url = try await recorder.stop()
            state = .idle
            onRestoreAppChrome?()
            onRecordingSaved?(url)
        } catch {
            state = .idle
            onRestoreAppChrome?()
            onError?(error)
        }
    }

    // MARK: - Helpers

    nonisolated static func makeOutputURL() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = movies.appendingPathComponent("MacCapture", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return folder.appendingPathComponent("Screen Recording \(formatter.string(from: Date())).mp4")
    }

    /// Converts a display-local top-left pixel rect to a display-local bottom-left AppKit point rect.
    private func displayLocalRectInPoints(regionInPixels: CGRect, display: CaptureDisplay) -> CGRect {
        let scale = max(display.scaleFactor, 1.0)
        let widthPts = regionInPixels.width / scale
        let heightPts = regionInPixels.height / scale
        let localX = regionInPixels.minX / scale
        let localYFromBottom = display.frameInPoints.height - (regionInPixels.minY / scale) - heightPts
        return CGRect(x: localX, y: localYFromBottom, width: widthPts, height: heightPts)
    }

    private func showRegionBorder(on display: CaptureDisplay, regionInPixels: CGRect) {
        hideRegionBorder()
        let localRect = displayLocalRectInPoints(regionInPixels: regionInPixels, display: display)
        let window = NSWindow(
            contentRect: display.frameInPoints,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let pixelText = "\(Int(regionInPixels.width))×\(Int(regionInPixels.height))"
        window.contentView = RecordingRegionBorderView(
            frame: CGRect(origin: .zero, size: display.frameInPoints.size),
            regionRectInView: localRect,
            pixelSizeText: pixelText
        )
        window.orderFrontRegardless()
        regionBorderWindow = window
    }

    private func hideRegionBorder() {
        regionBorderWindow?.orderOut(nil)
        regionBorderWindow = nil
    }

    private func showHUD(on display: CaptureDisplay, regionInPixels: CGRect?) {
        hudModel.elapsed = 0
        if let regionInPixels {
            hudModel.modeLabel = "\(Int(regionInPixels.width))×\(Int(regionInPixels.height))"
        } else {
            hudModel.modeLabel = "Full Screen"
        }

        let hosting = NSHostingView(rootView: RecordingHUDView(model: hudModel))
        let size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar + 1
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting

        let visible = display.visibleFrameInPoints
        if let regionInPixels {
            let localRect = displayLocalRectInPoints(regionInPixels: regionInPixels, display: display)
            let globalRegion = localRect.offsetBy(dx: display.frameInPoints.minX, dy: display.frameInPoints.minY)
            let clampedX = min(max(globalRegion.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            // Prefer placing the Stop HUD just below the recorded region; fallback to above or top of screen
            let belowY = globalRegion.minY - size.height - 10
            let aboveY = globalRegion.maxY + 10
            let originY: CGFloat
            if belowY >= visible.minY + 8 {
                originY = belowY
            } else if aboveY + size.height <= visible.maxY - 8 {
                originY = aboveY
            } else {
                originY = visible.maxY - size.height - 12
            }
            panel.setFrameOrigin(CGPoint(x: clampedX, y: originY))
        } else {
            panel.setFrameOrigin(CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - 12
            ))
        }
        panel.orderFrontRegardless()
        hudPanel = panel
    }

    private func hideHUD() {
        hudPanel?.orderOut(nil)
        hudPanel = nil
    }

    private func startTimer() {
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.hudModel.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        startDate = nil
    }

    private func observeFailures() {
        failureObserver = NotificationCenter.default.addObserver(
            forName: .screenRecorderDidFail, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stopRecording() }
        }
    }

    private func removeFailureObserver() {
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
    }
}
