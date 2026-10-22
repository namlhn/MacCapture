import ApplicationServices
import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - High-Speed Vertical Image Stitcher for Window / Browser Tab Scrolling

public enum StitchOutcome: Equatable, Sendable {
    case unchanged
    case stitched(addedHeight: Int, totalHeight: Int)
    case reachedMaxHeight(totalHeight: Int)
}

public final class ScrollingStitcher: @unchecked Sendable {
    private let lock = NSLock()
    public let maxPixelHeight: Int
    public private(set) var previousFrame: CGImage
    public private(set) var frameCount: Int = 1

    private var accumulatedBuffer: [UInt8]
    private var previousFrameBuffer: [UInt8]
    private var previousSignatures: [Int32]
    private var cachedAccumulatedImage: CGImage?

    public let width: Int
    public let frameHeight: Int
    public private(set) var currentHeight: Int

    public var accumulatedImage: CGImage {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedAccumulatedImage {
            return cached
        }
        let built = Self.makeCGImage(from: accumulatedBuffer, width: width, height: currentHeight) ?? previousFrame
        cachedAccumulatedImage = built
        return built
    }

    public init?(firstFrame: CGImage, maxPixelHeight: Int = 28_000) {
        let w = firstFrame.width
        let h = firstFrame.height
        guard w >= 8, h >= 8,
              let rgba = Self.extractRGBA(from: firstFrame) else {
            return nil
        }
        self.width = w
        self.frameHeight = h
        self.currentHeight = h
        self.maxPixelHeight = max(maxPixelHeight, h * 2)
        self.previousFrame = firstFrame
        self.cachedAccumulatedImage = firstFrame
        self.accumulatedBuffer = rgba
        self.accumulatedBuffer.reserveCapacity(w * min(maxPixelHeight, h * 8) * 4)
        self.previousFrameBuffer = rgba

        let marginX = max(8, w / 10)
        self.previousSignatures = Self.computeFastRowSignatures(
            buffer: rgba,
            width: w,
            height: h,
            startX: marginX,
            endX: max(marginX + 1, w - marginX)
        )
    }

    @discardableResult
    public func appendFrame(_ nextFrame: CGImage, forceAppend: Bool = false) -> StitchOutcome {
        lock.lock()
        defer { lock.unlock() }

        guard nextFrame.width == width, nextFrame.height == frameHeight else {
            return .unchanged
        }
        guard currentHeight < maxPixelHeight else {
            return .reachedMaxHeight(totalHeight: currentHeight)
        }
        guard let nextRGBA = Self.extractRGBA(from: nextFrame) else {
            return .unchanged
        }

        let w = width
        let h = frameHeight
        let marginX = max(8, w / 10)
        let activeStartX = marginX
        let activeEndX = max(activeStartX + 1, w - marginX)

        let nextSignatures = Self.computeFastRowSignatures(
            buffer: nextRGBA,
            width: w,
            height: h,
            startX: activeStartX,
            endX: activeEndX
        )

        // 1. Fast sticky top header & sticky bottom footer detection
        var stickyTop = 0
        let maxStickyTop = (h * 45) / 100
        previousSignatures.withUnsafeBufferPointer { prevSigPtr in
            nextSignatures.withUnsafeBufferPointer { nextSigPtr in
                while stickyTop < maxStickyTop {
                    let base = stickyTop * 4
                    let d = abs(prevSigPtr[base] - nextSigPtr[base])
                        + abs(prevSigPtr[base + 1] - nextSigPtr[base + 1])
                        + abs(prevSigPtr[base + 2] - nextSigPtr[base + 2])
                        + abs(prevSigPtr[base + 3] - nextSigPtr[base + 3])
                    if d < 28 {
                        stickyTop += 1
                    } else {
                        break
                    }
                }
            }
        }

        var stickyBottom = 0
        let maxStickyBottom = (h * 25) / 100
        previousSignatures.withUnsafeBufferPointer { prevSigPtr in
            nextSignatures.withUnsafeBufferPointer { nextSigPtr in
                while stickyBottom < maxStickyBottom {
                    let row = h - 1 - stickyBottom
                    let base = row * 4
                    let d = abs(prevSigPtr[base] - nextSigPtr[base])
                        + abs(prevSigPtr[base + 1] - nextSigPtr[base + 1])
                        + abs(prevSigPtr[base + 2] - nextSigPtr[base + 2])
                        + abs(prevSigPtr[base + 3] - nextSigPtr[base + 3])
                    if d < 28 {
                        stickyBottom += 1
                    } else {
                        break
                    }
                }
            }
        }

        let topBound = max(stickyTop, h / 12)
        var bottomBound = h - max(stickyBottom, h / 16)
        let usableHeight = bottomBound - topBound
        guard usableHeight >= 24 else {
            return .unchanged
        }

        // 2. Check if middle content is unchanged (deltaY == 0)
        let zeroShiftDiff = Self.fastSignatureBandDiff(
            sigA: previousSignatures,
            sigB: nextSignatures,
            startRowA: topBound,
            endRowA: bottomBound,
            deltaY: 0,
            rowStep: 2
        )

        if zeroShiftDiff < 3.0 && !forceAppend {
            return .unchanged
        }

        // 3. Two-stage Coarse-to-Fine Vertical Shift Search
        let minDelta = max(6, h / 50)
        let maxDelta = max(minDelta + 1, Int(Double(usableHeight) * 0.86))
        let coarseDeltaStep = max(1, (maxDelta - minDelta) > 120 ? 3 : 1)
        let coarseRowStep = max(1, usableHeight > 240 ? 4 : 1)

        var bestCoarseDeltas: [(deltaY: Int, score: Float)] = []
        bestCoarseDeltas.reserveCapacity((maxDelta - minDelta) / coarseDeltaStep + 2)

        var d = minDelta
        while d <= maxDelta {
            let overlapStartA = topBound + d
            if bottomBound - overlapStartA < 16 { break }
            let score = Self.fastSignatureBandDiff(
                sigA: previousSignatures,
                sigB: nextSignatures,
                startRowA: overlapStartA,
                endRowA: bottomBound,
                deltaY: d,
                rowStep: coarseRowStep
            )
            bestCoarseDeltas.append((d, score))
            d += coarseDeltaStep
        }

        bestCoarseDeltas.sort { $0.score < $1.score }
        let topPeaks = bestCoarseDeltas.prefix(4)

        var bestDeltaY: Int?
        var bestFineScore: Float = .greatestFiniteMagnitude

        for peak in topPeaks {
            let searchMin = max(minDelta, peak.deltaY - coarseDeltaStep)
            let searchMax = min(maxDelta, peak.deltaY + coarseDeltaStep)
            for candidateDelta in searchMin...searchMax {
                let fine = Self.bandDifference(
                    bufA: previousFrameBuffer,
                    bufB: nextRGBA,
                    width: w,
                    startX: activeStartX,
                    endX: activeEndX,
                    startRowA: topBound + candidateDelta,
                    endRowA: bottomBound,
                    deltaY: candidateDelta
                )
                if fine < bestFineScore {
                    bestFineScore = fine
                    bestDeltaY = candidateDelta
                }
            }
        }

        let resolvedDeltaY: Int
        if let matchDelta = bestDeltaY, bestFineScore < 29.0 {
            resolvedDeltaY = matchDelta
        } else if forceAppend && zeroShiftDiff >= 2.0 {
            resolvedDeltaY = max(usableHeight / 2, minDelta)
        } else {
            return .unchanged
        }

        let minBottomBound = max(topBound + resolvedDeltaY + 16, (h * 72) / 100)
        previousSignatures.withUnsafeBufferPointer { prevSigPtr in
            nextSignatures.withUnsafeBufferPointer { nextSigPtr in
                while bottomBound > minBottomBound {
                    let r = bottomBound - 1
                    let rMoved = r - resolvedDeltaY
                    let b0 = r * 4
                    let bMoved = rMoved * 4
                    let staticDiff = abs(prevSigPtr[b0] - nextSigPtr[b0])
                        + abs(prevSigPtr[b0 + 1] - nextSigPtr[b0 + 1])
                        + abs(prevSigPtr[b0 + 2] - nextSigPtr[b0 + 2])
                        + abs(prevSigPtr[b0 + 3] - nextSigPtr[b0 + 3])
                    let movedDiff = abs(prevSigPtr[b0] - nextSigPtr[bMoved])
                        + abs(prevSigPtr[b0 + 1] - nextSigPtr[bMoved + 1])
                        + abs(prevSigPtr[b0 + 2] - nextSigPtr[bMoved + 2])
                        + abs(prevSigPtr[b0 + 3] - nextSigPtr[bMoved + 3])
                    if staticDiff + 6 < movedDiff && staticDiff < 36 {
                        bottomBound -= 1
                    } else {
                        break
                    }
                }
            }
        }

        let allowedAdd = min(resolvedDeltaY, maxPixelHeight - currentHeight)
        guard allowedAdd > 0 else {
            return .reachedMaxHeight(totalHeight: currentHeight)
        }

        // 4. Fast memcpy splice of newly revealed rows into accumulatedBuffer
        let footerRows = h - bottomBound
        let spliceTargetY = currentHeight - footerRows
        let sourceStartRow = bottomBound - allowedAdd
        let rowsToCopy = allowedAdd + footerRows
        let newTotalHeight = currentHeight + allowedAdd

        let bytesPerRow = w * 4
        let addedBytes = allowedAdd * bytesPerRow
        let copyByteCount = rowsToCopy * bytesPerRow
        let srcStartByte = sourceStartRow * bytesPerRow
        let dstStartByte = spliceTargetY * bytesPerRow

        accumulatedBuffer.append(contentsOf: repeatElement(0, count: addedBytes))
        accumulatedBuffer.withUnsafeMutableBytes { dstRaw in
            nextRGBA.withUnsafeBytes { srcRaw in
                guard let dstBase = dstRaw.baseAddress, let srcBase = srcRaw.baseAddress else { return }
                memcpy(dstBase.advanced(by: dstStartByte), srcBase.advanced(by: srcStartByte), copyByteCount)
            }
        }

        currentHeight = newTotalHeight
        previousFrame = nextFrame
        previousFrameBuffer = nextRGBA
        previousSignatures = nextSignatures
        cachedAccumulatedImage = nil
        frameCount += 1

        if currentHeight >= maxPixelHeight {
            return .reachedMaxHeight(totalHeight: currentHeight)
        }
        return .stitched(addedHeight: allowedAdd, totalHeight: currentHeight)
    }

    // MARK: - Ultra-Fast Pointer Helpers

    private static func computeFastRowSignatures(
        buffer: [UInt8],
        width: Int,
        height: Int,
        startX: Int,
        endX: Int
    ) -> [Int32] {
        let bucketCount = 4
        let span = max(1, endX - startX)
        let xStep = max(2, span / 32)
        var sigs = [Int32](repeating: 0, count: height * bucketCount)

        buffer.withUnsafeBufferPointer { bufPtr in
            sigs.withUnsafeMutableBufferPointer { sigPtr in
                for y in 0..<height {
                    let rowOffset = y * width * 4
                    let sigBase = y * bucketCount
                    for b in 0..<bucketCount {
                        let bx0 = startX + (b * span) / bucketCount
                        let bx1 = max(bx0 + 1, startX + ((b + 1) * span) / bucketCount)
                        var sum: Int32 = 0
                        var count: Int32 = 0
                        var x = bx0
                        while x < bx1 {
                            let idx = rowOffset + x * 4
                            sum += Int32(bufPtr[idx]) + Int32(bufPtr[idx + 1]) + Int32(bufPtr[idx + 2])
                            count += 3
                            x += xStep
                        }
                        sigPtr[sigBase + b] = count > 0 ? (sum / count) : 0
                    }
                }
            }
        }
        return sigs
    }

    private static func fastSignatureBandDiff(
        sigA: [Int32],
        sigB: [Int32],
        startRowA: Int,
        endRowA: Int,
        deltaY: Int,
        rowStep: Int
    ) -> Float {
        guard endRowA > startRowA else { return .greatestFiniteMagnitude }
        var total: Int32 = 0
        var count: Int32 = 0
        sigA.withUnsafeBufferPointer { ptrA in
            sigB.withUnsafeBufferPointer { ptrB in
                var r = startRowA
                while r < endRowA {
                    let baseA = r * 4
                    let baseB = (r - deltaY) * 4
                    total += abs(ptrA[baseA] - ptrB[baseB])
                        + abs(ptrA[baseA + 1] - ptrB[baseB + 1])
                        + abs(ptrA[baseA + 2] - ptrB[baseB + 2])
                        + abs(ptrA[baseA + 3] - ptrB[baseB + 3])
                    count += 4
                    r += rowStep
                }
            }
        }
        return count > 0 ? Float(total) / Float(count) : .greatestFiniteMagnitude
    }

    private static func bandDifference(
        bufA: [UInt8],
        bufB: [UInt8],
        width: Int,
        startX: Int,
        endX: Int,
        startRowA: Int,
        endRowA: Int,
        deltaY: Int
    ) -> Float {
        guard endRowA > startRowA else { return .greatestFiniteMagnitude }
        let xStep = max(4, (endX - startX) / 40)
        let rStep = max(2, (endRowA - startRowA) / 48)
        var diffSum: Int = 0
        var samples: Int = 0

        bufA.withUnsafeBufferPointer { ptrA in
            bufB.withUnsafeBufferPointer { ptrB in
                var r = startRowA
                while r < endRowA {
                    let offsetA = r * width * 4
                    let offsetB = (r - deltaY) * width * 4
                    var x = startX
                    while x < endX {
                        let idxA = offsetA + x * 4
                        let idxB = offsetB + x * 4
                        diffSum += abs(Int(ptrA[idxA]) - Int(ptrB[idxB]))
                            + abs(Int(ptrA[idxA + 1]) - Int(ptrB[idxB + 1]))
                            + abs(Int(ptrA[idxA + 2]) - Int(ptrB[idxB + 2]))
                        samples += 3
                        x += xStep
                    }
                    r += rStep
                }
            }
        }
        return samples > 0 ? Float(diffSum) / Float(samples) : .greatestFiniteMagnitude
    }

    private static func extractRGBA(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ok = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }

    private static func makeCGImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, bytes.count == width * height * 4 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

// MARK: - Window / Browser Tab Scrolling Capture Controller

@MainActor
public protocol ScrollingCapturing: AnyObject {
    func captureScrollingWindow(
        window: CaptureWindow,
        clickPointInAppKit: CGPoint?,
        display: CaptureDisplay,
        captureEngine: CaptureEngineProtocol
    ) async throws -> CGImage
    func cleanup()
}

@MainActor
public final class ScrollingCaptureViewModel: ObservableObject {
    @Published public var windowTitle: String
    @Published public var previewImage: CGImage
    @Published public var frameCount: Int = 1
    @Published public var pixelWidth: Int
    @Published public var pixelHeight: Int
    @Published public var isAutoScrolling: Bool = true
    @Published public var statusText: String = "Đang tự động cuộn... Bấm Dừng (hoặc phím Space/Enter) khi muốn kết thúc"

    public var onTogglePause: (() -> Void)?
    public var onStopAndFinish: (() -> Void)?
    public var onCancel: (() -> Void)?

    public init(windowTitle: String, initialImage: CGImage) {
        self.windowTitle = windowTitle
        self.previewImage = initialImage
        self.pixelWidth = initialImage.width
        self.pixelHeight = initialImage.height
    }
}

@MainActor
public final class ScrollingCaptureController: ScrollingCapturing {
    private var borderWindow: NSWindow?
    private var hudPanel: NSPanel?
    private var samplingTask: Task<Void, Never>?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var stitcher: ScrollingStitcher?
    private var viewModel: ScrollingCaptureViewModel?
    private var unchangedTicks = 0
    private var isFinishing = false

    public init() {}

    public func captureScrollingWindow(
        window: CaptureWindow,
        clickPointInAppKit: CGPoint?,
        display: CaptureDisplay,
        captureEngine: CaptureEngineProtocol
    ) async throws -> CGImage {
        cleanup()
        isFinishing = false

        // Activate the target window's application so it receives scroll events
        if let targetApp = NSRunningApplication(processIdentifier: window.ownerPID) {
            targetApp.activate(options: [.activateAllWindows])
        }

        let scrollPointAppKit = Self.resolveScrollPointInAppKit(
            windowFrame: window.frameInPoints,
            userClickPoint: clickPointInAppKit
        )
        let scrollPointCG = Self.appKitPointToCGGlobalPoint(scrollPointAppKit, fallbackDisplay: display)

        try? await Task.sleep(nanoseconds: 80_000_000)

        let firstFrame = try await captureEngine.captureWindow(id: window.id)
        let createdStitcher = await Task.detached(priority: .userInitiated) {
            ScrollingStitcher(firstFrame: firstFrame)
        }.value

        guard let stitcher = createdStitcher else {
            return firstFrame
        }
        self.stitcher = stitcher

        let isTrusted = AXIsProcessTrusted()
        let vm = ScrollingCaptureViewModel(
            windowTitle: window.displayTitle,
            initialImage: firstFrame
        )
        if !isTrusted {
            vm.statusText = "Hãy lăn chuột / Trackpad trên cửa sổ để cuộn (hoặc cấp quyền Accessibility)"
        }
        self.viewModel = vm
        self.unchangedTicks = 0

        let stepScrollPixels = Int32(max(200, min(window.frameInPoints.height * 0.42, 460)))

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            self.continuation = continuation

            vm.onTogglePause = { [weak self] in
                guard let self, let vm = self.viewModel else { return }
                vm.isAutoScrolling.toggle()
                self.unchangedTicks = 0
                vm.statusText = vm.isAutoScrolling
                    ? "Đang tự động cuộn... Bấm Dừng khi muốn kết thúc"
                    : "Đã tạm dừng • Bạn có thể tự lăn chuột hoặc bấm Dừng & Hoàn thành"
            }

            vm.onStopAndFinish = { [weak self] in
                self?.finishWithStitchedImage(fallback: firstFrame)
            }

            vm.onCancel = { [weak self] in
                self?.finish(with: .failure(CaptureError.cancelled))
            }

            self.globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in
                    self?.handleKeyEvent(event, fallbackImage: firstFrame)
                }
            }
            self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.handleKeyEvent(event, fallbackImage: firstFrame) == true {
                    return nil
                }
                return event
            }

            let borderWin = ScrollingRegionBorderWindow(regionRectInAppKitPoints: window.frameInPoints)
            self.borderWindow = borderWin
            borderWin.orderFrontRegardless()

            let hud = Self.makeHUDPanel(
                viewModel: vm,
                regionRect: window.frameInPoints,
                displayVisibleFrame: display.visibleFrameInPoints
            )
            self.hudPanel = hud
            hud.orderFrontRegardless()

            // Background scroll & capture loop (never blocks @MainActor!)
            self.samplingTask = Task { [weak self] in
                while !Task.isCancelled {
                    let isAuto = await MainActor.run { self?.viewModel?.isAutoScrolling ?? false }

                    if isAuto {
                        Self.postScrollBurstOnBackground(
                            atCGPoint: scrollPointCG,
                            totalScrollPixels: stepScrollPixels
                        )
                        try? await Task.sleep(nanoseconds: 110_000_000)
                    } else {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }

                    guard !Task.isCancelled else { break }
                    await self?.sampleAndStitchWindow(
                        windowID: window.id,
                        captureEngine: captureEngine,
                        fallbackImage: firstFrame
                    )
                }
            }
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent, fallbackImage: CGImage) -> Bool {
        if event.keyCode == 53 {
            finish(with: .failure(CaptureError.cancelled))
            return true
        } else if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
            finishWithStitchedImage(fallback: fallbackImage)
            return true
        }
        return false
    }

    private func finishWithStitchedImage(fallback: CGImage) {
        guard !isFinishing else { return }
        isFinishing = true
        samplingTask?.cancel()
        viewModel?.statusText = "Đang hoàn tất ghép ảnh..."
        let currentStitcher = self.stitcher
        Task.detached(priority: .userInitiated) { [weak self] in
            let finalImage = currentStitcher?.accumulatedImage ?? fallback
            await MainActor.run {
                self?.finish(with: .success(finalImage))
            }
        }
    }

    public func cleanup() {
        samplingTask?.cancel()
        samplingTask = nil
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        borderWindow?.orderOut(nil)
        borderWindow = nil
        hudPanel?.orderOut(nil)
        hudPanel = nil
    }

    private func sampleAndStitchWindow(
        windowID: UInt32,
        captureEngine: CaptureEngineProtocol,
        fallbackImage: CGImage
    ) async {
        guard !isFinishing, let stitcher, let vm = viewModel else { return }
        guard let nextFrame = try? await captureEngine.captureWindow(id: windowID) else {
            return
        }
        guard !isFinishing, !Task.isCancelled else { return }

        // Run heavy pixel extraction & overlap search off the MainActor!
        let (outcome, newFrameCount) = await Task.detached(priority: .userInitiated) {
            let res = stitcher.appendFrame(nextFrame, forceAppend: false)
            return (res, stitcher.frameCount)
        }.value

        guard !isFinishing, !Task.isCancelled else { return }

        switch outcome {
        case .unchanged:
            if vm.isAutoScrolling {
                unchangedTicks += 1
                if unchangedTicks >= 4 && newFrameCount >= 2 {
                    vm.statusText = "Đã cuộn đến cuối trang! Đang mở Editor..."
                    finishWithStitchedImage(fallback: fallbackImage)
                } else if unchangedTicks >= 5 && newFrameCount == 1 {
                    // Pause auto-scroll so we never spin endlessly if the window cannot auto-scroll
                    vm.isAutoScrolling = false
                    unchangedTicks = 0
                    vm.statusText = "Hãy tự lăn chuột / Trackpad trên cửa sổ rồi bấm Hoàn thành"
                }
            }
        case .stitched(let added, let totalHeight):
            unchangedTicks = 0
            vm.previewImage = nextFrame
            vm.frameCount = newFrameCount
            vm.pixelHeight = totalHeight
            vm.statusText = "Đã ghép +\(added) px (Tổng: \(totalHeight) px) • Bấm Dừng bất kỳ lúc nào"
        case .reachedMaxHeight(let totalHeight):
            vm.frameCount = newFrameCount
            vm.pixelHeight = totalHeight
            finishWithStitchedImage(fallback: fallbackImage)
        }
    }

    private func finish(with result: Result<CGImage, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cleanup()
        cont.resume(with: result)
    }

    private static func resolveScrollPointInAppKit(
        windowFrame: CGRect,
        userClickPoint: CGPoint?
    ) -> CGPoint {
        let safeMinX = windowFrame.minX + min(80, windowFrame.width * 0.2)
        let safeMaxX = windowFrame.maxX - min(80, windowFrame.width * 0.2)
        let safeMinY = windowFrame.minY + min(60, windowFrame.height * 0.18)
        let safeMaxY = windowFrame.maxY - min(110, windowFrame.height * 0.28)

        if let click = userClickPoint, windowFrame.contains(click), safeMaxX > safeMinX, safeMaxY > safeMinY {
            return CGPoint(
                x: min(max(click.x, safeMinX), safeMaxX),
                y: min(max(click.y, safeMinY), safeMaxY)
            )
        }
        return CGPoint(
            x: windowFrame.midX,
            y: windowFrame.minY + windowFrame.height * 0.45
        )
    }

    private static func appKitPointToCGGlobalPoint(
        _ appKitPoint: CGPoint,
        fallbackDisplay: CaptureDisplay
    ) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? fallbackDisplay.frameInPoints.height
        return CGPoint(
            x: appKitPoint.x,
            y: primaryHeight - appKitPoint.y
        )
    }

    nonisolated private static func postScrollBurstOnBackground(
        atCGPoint cgPoint: CGPoint,
        totalScrollPixels: Int32
    ) {
        // Never call CGWarpMouseCursorPosition here (which freezes mouse input for 250ms)!
        // Simply set event.location = cgPoint and post to cghidEventTap.
        let ticks = 4
        let perTick = -max(Int32(45), totalScrollPixels / Int32(ticks))
        for _ in 0..<ticks {
            if let pixelEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: perTick,
                wheel2: 0,
                wheel3: 0
            ) {
                pixelEvent.location = cgPoint
                pixelEvent.post(tap: .cghidEventTap)
            }
            usleep(6_000)
        }
    }

    private static func makeHUDPanel(
        viewModel: ScrollingCaptureViewModel,
        regionRect: CGRect,
        displayVisibleFrame: CGRect
    ) -> NSPanel {
        let hudSize = CGSize(width: 286, height: 300)
        var originX = regionRect.maxX + 14
        if originX + hudSize.width > displayVisibleFrame.maxX - 8 {
            originX = regionRect.minX - hudSize.width - 14
        }
        if originX < displayVisibleFrame.minX + 8 {
            originX = displayVisibleFrame.maxX - hudSize.width - 14
        }
        let originY = min(
            max(regionRect.midY - hudSize.height / 2, displayVisibleFrame.minY + 12),
            displayVisibleFrame.maxY - hudSize.height - 12
        )

        let panel = NSPanel(
            contentRect: CGRect(origin: CGPoint(x: originX, y: originY), size: hudSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ScrollingCaptureHUDView(viewModel: viewModel))
        return panel
    }
}

// MARK: - Pass-through Window Highlight Frame

private final class ScrollingRegionBorderWindow: NSWindow {
    private static let outset: CGFloat = 6

    init(regionRectInAppKitPoints: CGRect) {
        let frame = regionRectInAppKitPoints.insetBy(dx: -Self.outset, dy: -Self.outset)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = ScrollingBorderOverlayView(
            frame: CGRect(origin: .zero, size: frame.size),
            outset: Self.outset
        )
    }
}

private final class ScrollingBorderOverlayView: NSView {
    private let outset: CGFloat

    init(frame: NSRect, outset: CGFloat) {
        self.outset = outset
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let strokeRect = bounds.insetBy(dx: 2.5, dy: 2.5)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemCyan.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineDash(phase: 0, lengths: [8, 4])
        ctx.stroke(strokeRect)
        ctx.restoreGState()
    }
}

// MARK: - Floating Scrolling Capture HUD View

private struct ScrollingCaptureHUDView: View {
    @ObservedObject var viewModel: ScrollingCaptureViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                AppLogoBadgeView(size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.windowTitle)
                        .font(.system(size: 11.5, weight: .bold))
                        .lineLimit(1)
                    Text("Đã ghép \(viewModel.frameCount) khung • \(viewModel.pixelWidth)×\(viewModel.pixelHeight) px")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.28))

                Image(decorative: viewModel.previewImage, scale: 1.0)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .padding(6)
            }
            .frame(height: 128)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )

            Text(viewModel.statusText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28)

            Button {
                viewModel.onStopAndFinish?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Dừng & Hoàn thành (Space)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.red)
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    viewModel.onTogglePause?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isAutoScrolling ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(viewModel.isAutoScrolling ? "Tạm dừng" : "Tiếp tục cuộn")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.onCancel?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Hủy (Esc)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
        )
    }
}
