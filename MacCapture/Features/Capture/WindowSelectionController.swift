import AppKit
import CoreGraphics
import Foundation

@MainActor
public protocol WindowSelecting: AnyObject {
    func selectWindow(windows: [CaptureWindow], displays: [CaptureDisplay]) async throws -> UInt32
    func cleanup()
}

@MainActor
public final class WindowSelectionController: WindowSelecting {
    private var overlayWindows: [NSWindow] = []
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<UInt32, Error>?
    public private(set) var lastSelectedClickPointInAppKit: CGPoint?

    public init() {}

    public func selectWindow(windows: [CaptureWindow], displays: [CaptureDisplay]) async throws -> UInt32 {
        cleanup()
        guard !windows.isEmpty else {
            throw CaptureError.captureFailed("No capturable windows are currently visible.")
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt32, Error>) in
            self.continuation = continuation

            self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    self?.finish(with: .failure(CaptureError.cancelled))
                    return nil
                }
                return event
            }

            for display in displays {
                let window = WindowPickerOverlayWindow(
                    display: display,
                    candidateWindows: windows,
                    onSelect: { [weak self] windowID, globalClickPoint in
                        self?.lastSelectedClickPointInAppKit = globalClickPoint
                        self?.finish(with: .success(windowID))
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
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func finish(with result: Result<UInt32, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cleanup()
        cont.resume(with: result)
    }
}

private final class WindowPickerOverlayWindow: NSWindow {
    init(
        display: CaptureDisplay,
        candidateWindows: [CaptureWindow],
        onSelect: @escaping (UInt32, CGPoint) -> Void,
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
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = WindowSelectionOverlayView(
            display: display,
            candidateWindows: candidateWindows,
            onSelect: onSelect,
            onCancel: onCancel
        )
        self.contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class WindowSelectionOverlayView: NSView {
    private let display: CaptureDisplay
    private let candidateWindows: [CaptureWindow]
    private let onSelect: (UInt32, CGPoint) -> Void
    private let onCancel: () -> Void
    private var hoveredWindow: CaptureWindow?

    init(
        display: CaptureDisplay,
        candidateWindows: [CaptureWindow],
        onSelect: @escaping (UInt32, CGPoint) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.display = display
        self.candidateWindows = candidateWindows
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: CGRect(origin: .zero, size: display.frameInPoints.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = CGPoint(
            x: display.frameInPoints.minX + localPoint.x,
            y: display.frameInPoints.minY + localPoint.y
        )
        let matched = candidateWindows.first { $0.frameInPoints.contains(globalPoint) }
        if matched != hoveredWindow {
            hoveredWindow = matched
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = CGPoint(
            x: display.frameInPoints.minX + localPoint.x,
            y: display.frameInPoints.minY + localPoint.y
        )
        if let hoveredWindow {
            onSelect(hoveredWindow.id, globalPoint)
        } else if let matched = candidateWindows.first(where: { $0.frameInPoints.contains(globalPoint) }) {
            onSelect(matched.id, globalPoint)
        } else {
            onCancel()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        context.fill(bounds)

        drawInstructionBanner()

        if let hovered = hoveredWindow {
            let localRect = CGRect(
                x: hovered.frameInPoints.minX - display.frameInPoints.minX,
                y: hovered.frameInPoints.minY - display.frameInPoints.minY,
                width: hovered.frameInPoints.width,
                height: hovered.frameInPoints.height
            )
            let clamped = CoordinateConverter.clampRect(localRect, to: bounds)
            if clamped.width > 0, clamped.height > 0 {
                context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.18).cgColor)
                context.fill(clamped)

                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(3.0)
                context.stroke(clamped.insetBy(dx: 1.5, dy: 1.5))

                drawTitlePill(title: hovered.displayTitle, near: clamped)
            }
        }
    }

    private func drawTitlePill(title: String, near rect: CGRect) {
        let nsText = title as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = nsText.size(withAttributes: attributes)
        let pillW = min(size.width + 16, bounds.width - 16)
        let pillH = size.height + 8
        let pillX = min(max(rect.minX, bounds.minX + 8), bounds.maxX - pillW - 8)
        let pillY = min(max(rect.maxY - pillH - 8, bounds.minY + 8), bounds.maxY - pillH - 8)
        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)

        let path = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.82).setFill()
        path.fill()
        nsText.draw(
            with: pillRect.insetBy(dx: 8, dy: 4),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }

    private func drawInstructionBanner() {
        let text = "Click vào Cửa sổ hoặc Tab trình duyệt cần chụp • Nhấn Esc để hủy" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let pillRect = CGRect(
            x: bounds.midX - (size.width + 28) / 2,
            y: bounds.maxY - 64,
            width: size.width + 28,
            height: size.height + 14
        )
        let path = NSBezierPath(roundedRect: pillRect, xRadius: 9, yRadius: 9)
        NSColor.black.withAlphaComponent(0.78).setFill()
        path.fill()
        text.draw(at: CGPoint(x: pillRect.minX + 14, y: pillRect.minY + 7), withAttributes: attributes)
    }
}
