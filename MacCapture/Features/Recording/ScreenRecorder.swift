import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

public enum RecordingMode: String, Codable, CaseIterable, Sendable {
    case region
    case fullscreen

    public var displayName: String {
        switch self {
        case .region: return "Record Region"
        case .fullscreen: return "Record Fullscreen"
        }
    }

    public var symbolName: String {
        switch self {
        case .region: return "record.circle"
        case .fullscreen: return "rectangle.inset.filled.badge.record"
        }
    }
}

public enum RecordingError: Error, LocalizedError, Sendable {
    case alreadyRecording
    case notRecording
    case displayNotFound(UInt32)
    case invalidRegion
    case writerFailed(String)
    case streamFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "A recording is already in progress."
        case .notRecording: return "No recording is in progress."
        case .displayNotFound(let id): return "Target display (\(id)) is no longer available."
        case .invalidRegion: return "Selected recording region is too small."
        case .writerFailed(let reason): return "Could not write video file: \(reason)"
        case .streamFailed(let reason): return "Screen recording failed: \(reason)"
        }
    }
}

public protocol ScreenRecording: AnyObject, Sendable {
    var isRecording: Bool { get }
    /// - Parameters:
    ///   - displayID: Display to record.
    ///   - regionInPixels: Region (top-left origin, display-local pixels) or `nil` for the whole display.
    ///   - scaleFactor: Backing scale of the display (pixels per point).
    func start(displayID: UInt32, regionInPixels: CGRect?, scaleFactor: CGFloat, outputURL: URL) async throws
    func stop() async throws -> URL
}

/// Records a display (or part of it) to an H.264 `.mp4` using ScreenCaptureKit + AVAssetWriter.
public final class ScreenRecorder: NSObject, ScreenRecording, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let sampleQueue = DispatchQueue(label: "maccapture.recorder.samples")
    private let stateLock = NSLock()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var streamError: Error?
    private var recording = false

    public override init() { super.init() }

    public var isRecording: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recording
    }

    public func start(displayID: UInt32, regionInPixels: CGRect?, scaleFactor: CGFloat, outputURL: URL) async throws {
        if isRecording { throw RecordingError.alreadyRecording }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecordingError.displayNotFound(displayID)
        }

        let scale = max(scaleFactor, 1)
        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = false
        config.queueDepth = 6
        config.scalesToFit = false

        var pixelWidth = Int((CGFloat(display.width) * scale).rounded())
        var pixelHeight = Int((CGFloat(display.height) * scale).rounded())

        if let region = regionInPixels {
            let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
            let clamped = region.integral.intersection(bounds)
            guard !clamped.isNull, clamped.width >= 16, clamped.height >= 16 else {
                throw RecordingError.invalidRegion
            }
            // sourceRect is in display-local points with a top-left origin.
            config.sourceRect = CGRect(
                x: clamped.minX / scale,
                y: clamped.minY / scale,
                width: clamped.width / scale,
                height: clamped.height / scale
            )
            pixelWidth = Int(clamped.width)
            pixelHeight = Int(clamped.height)
        }
        // H.264 requires even dimensions.
        pixelWidth -= pixelWidth % 2
        pixelHeight -= pixelHeight % 2
        config.width = pixelWidth
        config.height = pixelHeight

        // Keep MacCapture's own UI (recording HUD, overlays) out of the video.
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == currentPID }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        try? FileManager.default.removeItem(at: outputURL)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw RecordingError.writerFailed(error.localizedDescription)
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(pixelWidth * pixelHeight * 4, 2_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecordingError.writerFailed("Cannot add video input.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        stateLock.lock()
        self.writer = writer
        self.videoInput = input
        self.outputURL = outputURL
        self.stream = stream
        self.sessionStarted = false
        self.streamError = nil
        stateLock.unlock()

        do {
            try await stream.startCapture()
        } catch {
            writer.cancelWriting()
            stateLock.lock()
            resetLocked()
            stateLock.unlock()
            throw RecordingError.streamFailed(error.localizedDescription)
        }

        stateLock.lock()
        recording = true
        stateLock.unlock()
    }

    public func stop() async throws -> URL {
        stateLock.lock()
        guard recording, let stream, let writer, let input = videoInput, let url = outputURL else {
            stateLock.unlock()
            throw RecordingError.notRecording
        }
        recording = false
        let started = sessionStarted
        stateLock.unlock()

        try? await stream.stopCapture()

        // Drain any in-flight sample callbacks before finalizing.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sampleQueue.async { cont.resume() }
        }

        defer {
            stateLock.lock()
            resetLocked()
            stateLock.unlock()
        }

        guard started else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw RecordingError.writerFailed("No frames were captured.")
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        return url
    }

    private func resetLocked() {
        stream = nil
        writer = nil
        videoInput = nil
        outputURL = nil
        sessionStarted = false
        recording = false
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Only complete frames carry pixel data (idle/blank frames lack this status).
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else {
            return
        }

        stateLock.lock()
        guard let writer, let input = videoInput, writer.status == .writing else {
            stateLock.unlock()
            return
        }
        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        stateLock.unlock()

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateLock.lock()
        streamError = error
        stateLock.unlock()
        NotificationCenter.default.post(name: .screenRecorderDidFail, object: self, userInfo: ["error": error])
    }
}

public extension Notification.Name {
    static let screenRecorderDidFail = Notification.Name("maccapture.screenRecorderDidFail")
}
