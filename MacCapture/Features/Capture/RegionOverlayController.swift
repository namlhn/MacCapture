import AppKit
import CoreGraphics
import Foundation

public struct RegionSelectionResult: Equatable, Sendable {
    public let displayID: UInt32
    public let rectInPixels: CGRect

    public init(displayID: UInt32, rectInPixels: CGRect) {
        self.displayID = displayID
        self.rectInPixels = rectInPixels
    }
}

@MainActor
public protocol RegionSelecting: AnyObject {
    func selectRegion(displays: [CaptureDisplay]) async throws -> RegionSelectionResult
    func cleanup()
}

@MainActor
public final class RegionOverlayController: RegionSelecting {
    private var overlayWindows: [NSWindow] = []
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<RegionSelectionResult, Error>?
    private var hasPushedCursor = false

    public init() {}

    public func selectRegion(displays: [CaptureDisplay]) async throws -> RegionSelectionResult {
        cleanup()
        guard !displays.isEmpty else {
            throw CaptureError.noDisplaysAvailable
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RegionSelectionResult, Error>) in
            self.continuation = continuation

            NSCursor.crosshair.push()
            self.hasPushedCursor = true

            self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    self?.finish(with: .failure(CaptureError.cancelled))
                    return nil
                }
                return event
            }

            for display in displays {
                let window = OverlayWindow(
                    display: display,
                    onComplete: { [weak self] pixelRect in
                        self?.finish(with: .success(RegionSelectionResult(displayID: display.id, rectInPixels: pixelRect)))
                    },
                    onCancel: { [weak self] in
                        self?.finish(with: .failure(CaptureError.cancelled))
                    }
                )
                overlayWindows.append(window)
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func cleanup() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if hasPushedCursor {
            NSCursor.pop()
            hasPushedCursor = false
        }
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func finish(with result: Result<RegionSelectionResult, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cleanup()
        cont.resume(with: result)
    }
}

private final class OverlayWindow: NSWindow {
    init(
        display: CaptureDisplay,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        super.init(
            contentRect: display.frameInPoints,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = RegionSelectionOverlayView(
            display: display,
            onComplete: onComplete,
            onCancel: onCancel
        )
        self.contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RegionSelectionOverlayView: NSView {
    private let display: CaptureDisplay
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    private var dragStartInView: CGPoint?
    private var currentDragInView: CGPoint?

    init(
        display: CaptureDisplay,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.display = display
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: CGRect(origin: .zero, size: display.frameInPoints.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStartInView = point
        currentDragInView = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentDragInView = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStartInView else { return }
        let end = convert(event.locationInWindow, from: nil)
        dragStartInView = nil
        currentDragInView = nil
        needsDisplay = true

        let localRect = CoordinateConverter.normalizedDragRect(from: start, to: end)
        let globalRect = CGRect(
            x: display.frameInPoints.minX + localRect.minX,
            y: display.frameInPoints.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
        let pixelRect = CoordinateConverter.appKitGlobalRectToDisplayPixelRect(globalRect, display: display)

        if CoordinateConverter.isValidSelection(pixelRect: pixelRect) {
            onComplete(pixelRect)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fill(bounds)

        drawInstructionBanner()

        guard let start = dragStartInView, let current = currentDragInView else { return }
        let selectionRect = CoordinateConverter.clampRect(
            CoordinateConverter.normalizedDragRect(from: start, to: current),
            to: bounds
        )
        guard selectionRect.width > 0, selectionRect.height > 0 else { return }

        context.clear(selectionRect)
        context.setFillColor(NSColor.white.withAlphaComponent(0.02).cgColor)
        context.fill(selectionRect)

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2.0)
        context.stroke(selectionRect.insetBy(dx: 1, dy: 1))

        let pixelW = Int((selectionRect.width * display.scaleFactor).rounded())
        let pixelH = Int((selectionRect.height * display.scaleFactor).rounded())
        drawDimensionBadge(text: "\(pixelW) × \(pixelH) px", near: selectionRect)
    }

    private func drawInstructionBanner() {
        let text = "Drag to select capture region • Press Esc to cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let pillRect = CGRect(
            x: bounds.midX - (size.width + 24) / 2,
            y: bounds.maxY - 64,
            width: size.width + 24,
            height: size.height + 12
        )
        let path = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        path.fill()
        text.draw(at: CGPoint(x: pillRect.minX + 12, y: pillRect.minY + 6), withAttributes: attributes)
    }

    private func drawDimensionBadge(text: String, near rect: CGRect) {
        let nsText = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = nsText.size(withAttributes: attributes)
        let badgeWidth = size.width + 14
        let badgeHeight = size.height + 8
        let badgeX = min(max(rect.minX, bounds.minX + 4), bounds.maxX - badgeWidth - 4)
        let badgeY = rect.minY >= badgeHeight + 8 ? rect.minY - badgeHeight - 6 : rect.minY + 6
        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)

        let path = NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.8).setFill()
        path.fill()
        nsText.draw(at: CGPoint(x: badgeRect.minX + 7, y: badgeRect.minY + 4), withAttributes: attributes)
    }
}
