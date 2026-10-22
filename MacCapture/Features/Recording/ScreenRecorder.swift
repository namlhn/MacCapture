import AVFoundation
import CoreAudio
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

public struct RecordingAudioOptions: Equatable, Sendable {
    public var recordSystemAudio: Bool
    public var recordMicrophone: Bool

    public init(recordSystemAudio: Bool = true, recordMicrophone: Bool = true) {
        self.recordSystemAudio = recordSystemAudio
        self.recordMicrophone = recordMicrophone
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
    func start(
        displayID: UInt32,
        regionInPixels: CGRect?,
        scaleFactor: CGFloat,
        audioOptions: RecordingAudioOptions,
        outputURL: URL
    ) async throws
    func stop() async throws -> URL
}

/// Thread-safe stereo Float32 ring buffer used to mix ScreenCaptureKit system audio into microphone audio.
private final class StereoAudioRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let capacityFrames: Int
    private var left: [Float]
    private var right: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private var availableFrames = 0

    init(capacityFrames: Int = 48000 * 2) {
        self.capacityFrames = capacityFrames
        self.left = [Float](repeating: 0, count: capacityFrames)
        self.right = [Float](repeating: 0, count: capacityFrames)
    }

    func reset() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        availableFrames = 0
        lock.unlock()
    }

    func append(sampleBuffer: CMSampleBuffer) {
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 2,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        let listSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        let ablPtr = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }
        _ = audioBufferList

        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, !buffers.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        if buffers.count >= 2,
           let lPtr = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let rPtr = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
            for i in 0..<frameCount {
                left[writeIndex] = lPtr[i]
                right[writeIndex] = rPtr[i]
                writeIndex = (writeIndex + 1) % capacityFrames
            }
        } else if let ptr = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
            let channels = Int(max(buffers[0].mNumberChannels, 1))
            for i in 0..<frameCount {
                let l = ptr[i * channels]
                let r = channels > 1 ? ptr[i * channels + 1] : l
                left[writeIndex] = l
                right[writeIndex] = r
                writeIndex = (writeIndex + 1) % capacityFrames
            }
        } else {
            return
        }

        availableFrames += frameCount
        if availableFrames > capacityFrames {
            let overflow = availableFrames - capacityFrames
            readIndex = (readIndex + overflow) % capacityFrames
            availableFrames = capacityFrames
        }
    }

    /// Mixes queued stereo frames into an interleaved stereo Float32 buffer in-place.
    func mixIntoInterleavedStereo(_ dst: UnsafeMutablePointer<Float>, frameCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        let toMix = min(frameCount, availableFrames)
        guard toMix > 0 else { return }

        for i in 0..<toMix {
            let l = dst[i * 2] + left[readIndex]
            let r = dst[i * 2 + 1] + right[readIndex]
            dst[i * 2] = min(max(l, -1.0), 1.0)
            dst[i * 2 + 1] = min(max(r, -1.0), 1.0)
            readIndex = (readIndex + 1) % capacityFrames
        }
        availableFrames -= toMix
    }
}

/// Records a display (or part of it) with optional System Audio + Microphone Voice to an `.mp4` file.
public final class ScreenRecorder: NSObject, ScreenRecording, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let sampleQueue = DispatchQueue(label: "maccapture.recorder.samples")
    private let stateLock = NSLock()
    private let systemAudioRingBuffer = StereoAudioRingBuffer()

    private var stream: SCStream?
    private var micSession: AVCaptureSession?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var sessionStartPTS: CMTime = .invalid
    private var lastAudioPTS: CMTime = .invalid
    private var useMicAsMasterAudioClock = false
    private var mixSystemAudioIntoMic = false
    private var streamError: Error?
    private var recording = false

    public override init() { super.init() }

    public var isRecording: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recording
    }

    public func start(
        displayID: UInt32,
        regionInPixels: CGRect?,
        scaleFactor: CGFloat,
        audioOptions: RecordingAudioOptions = RecordingAudioOptions(),
        outputURL: URL
    ) async throws {
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
        config.capturesAudio = audioOptions.recordSystemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
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

        // Keep MacCapture's own UI (recording HUD, region border) out of the video.
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

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(pixelWidth * pixelHeight * 4, 2_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
            ],
        ])
        vInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(vInput) else {
            throw RecordingError.writerFailed("Cannot add video input.")
        }
        writer.add(vInput)

        // Set up optional microphone capture session if requested & permitted
        var configuredMicSession: AVCaptureSession?
        if audioOptions.recordMicrophone,
           AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let micDevice = AVCaptureDevice.default(for: .audio),
           let micDeviceInput = try? AVCaptureDeviceInput(device: micDevice) {
            let session = AVCaptureSession()
            let micOutput = AVCaptureAudioDataOutput()
            micOutput.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            micOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            if session.canAddInput(micDeviceInput), session.canAddOutput(micOutput) {
                session.addInput(micDeviceInput)
                session.addOutput(micOutput)
                configuredMicSession = session
            }
        }

        let hasMic = configuredMicSession != nil
        let hasSystemAudio = audioOptions.recordSystemAudio
        var aInput: AVAssetWriterInput?

        if hasMic || hasSystemAudio {
            let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            audioWriterInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioWriterInput) {
                writer.add(audioWriterInput)
                aInput = audioWriterInput
            }
        }

        guard writer.startWriting() else {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if hasSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }

        systemAudioRingBuffer.reset()

        stateLock.lock()
        self.writer = writer
        self.videoInput = vInput
        self.audioInput = aInput
        self.micSession = configuredMicSession
        self.outputURL = outputURL
        self.stream = stream
        self.sessionStarted = false
        self.sessionStartPTS = .invalid
        self.lastAudioPTS = .invalid
        self.useMicAsMasterAudioClock = hasMic
        self.mixSystemAudioIntoMic = hasMic && hasSystemAudio
        self.streamError = nil
        stateLock.unlock()

        do {
            try await stream.startCapture()
            configuredMicSession?.startRunning()
        } catch {
            configuredMicSession?.stopRunning()
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
        guard recording, let stream, let writer, let vInput = videoInput, let url = outputURL else {
            stateLock.unlock()
            throw RecordingError.notRecording
        }
        let aInput = audioInput
        let mic = micSession
        recording = false
        let started = sessionStarted
        stateLock.unlock()

        mic?.stopRunning()
        try? await stream.stopCapture()

        // Drain sample queue before finalizing the file.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sampleQueue.async {
                cont.resume()
            }
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

        vInput.markAsFinished()
        aInput?.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        return url
    }

    private func resetLocked() {
        stream = nil
        micSession = nil
        writer = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        sessionStarted = false
        sessionStartPTS = .invalid
        lastAudioPTS = .invalid
        useMicAsMasterAudioClock = false
        mixSystemAudioIntoMic = false
        recording = false
        systemAudioRingBuffer.reset()
    }

    // MARK: - SCStreamOutput (Video & System Audio)

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: raw) == .complete else {
                return
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            stateLock.lock()
            guard recording, let writer, let vInput = videoInput, writer.status == .writing else {
                stateLock.unlock()
                return
            }
            if !sessionStarted {
                writer.startSession(atSourceTime: pts)
                sessionStarted = true
                sessionStartPTS = pts
            }
            stateLock.unlock()

            if vInput.isReadyForMoreMediaData {
                vInput.append(sampleBuffer)
            }

        case .audio:
            stateLock.lock()
            let isRec = recording
            let started = sessionStarted
            let micMaster = useMicAsMasterAudioClock
            let shouldMix = mixSystemAudioIntoMic
            stateLock.unlock()

            guard isRec, started else { return }

            if micMaster {
                if shouldMix {
                    systemAudioRingBuffer.append(sampleBuffer: sampleBuffer)
                }
            } else {
                appendAudioSampleBuffer(sampleBuffer)
            }

        default:
            break
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate (Microphone Voice)

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid else { return }

        stateLock.lock()
        let isRec = recording
        let started = sessionStarted
        let shouldMix = mixSystemAudioIntoMic
        stateLock.unlock()

        guard isRec, started else { return }

        if shouldMix {
            mixSystemAudioInPlace(into: sampleBuffer)
        }
        appendAudioSampleBuffer(sampleBuffer)
    }

    private func mixSystemAudioInPlace(into micSampleBuffer: CMSampleBuffer) {
        var blockBuffer: CMBlockBuffer?
        var abl = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 0, mData: nil)
        )
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            micSampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr,
              let dataPtr = abl.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
            return
        }
        let frames = CMSampleBufferGetNumSamples(micSampleBuffer)
        systemAudioRingBuffer.mixIntoInterleavedStereo(dataPtr, frameCount: frames)
    }

    private func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        stateLock.lock()
        guard recording,
              sessionStarted,
              let writer,
              let aInput = audioInput,
              writer.status == .writing else {
            stateLock.unlock()
            return
        }
        if sessionStartPTS.isValid, CMTimeCompare(pts, sessionStartPTS) < 0 {
            stateLock.unlock()
            return
        }
        if lastAudioPTS.isValid, CMTimeCompare(pts, lastAudioPTS) <= 0 {
            stateLock.unlock()
            return
        }
        lastAudioPTS = pts
        stateLock.unlock()

        if aInput.isReadyForMoreMediaData {
            aInput.append(sampleBuffer)
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
