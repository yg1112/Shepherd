import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine

/// Manages system audio capture using ScreenCaptureKit
@MainActor
final class AudioCaptureManager: NSObject, ObservableObject {
    static let shared = AudioCaptureManager()

    @Published var isCapturing: Bool = false
    @Published var audioLevel: Float = 0.0

    private var stream: SCStream?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    // Audio settings for Whisper (16kHz mono)
    private let targetSampleRate: Double = 16000
    private let targetChannels: Int = 1

    // VAD settings
    private var silenceFrameCount: Int = 0
    private let silenceThreshold: Float = 0.01
    private let silenceFramesForCut: Int = 8000  // ~0.5s at 16kHz

    // Callbacks
    var onAudioChunkReady: (([Float]) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Start/Stop Capture

    func startCapture() async throws {
        guard !isCapturing else { return }

        NSLog("[Shepherd Audio] Starting system audio capture...")

        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplay
        }

        // Create filter - capture entire display audio
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // Configure stream for audio only
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // Prevent feedback
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = targetChannels

        // We still need to set some video properties even if we don't want video
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 FPS minimum
        config.showsCursor = false

        // Create and start stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)

        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        try await stream?.startCapture()

        await MainActor.run {
            self.isCapturing = true
        }

        NSLog("[Shepherd Audio] System audio capture started")
    }

    func stopCapture() async {
        guard isCapturing else { return }

        NSLog("[Shepherd Audio] Stopping system audio capture...")

        do {
            try await stream?.stopCapture()
        } catch {
            NSLog("[Shepherd Audio] Error stopping capture: \(error)")
        }

        stream = nil
        isCapturing = false
        audioBuffer.removeAll()

        NSLog("[Shepherd Audio] System audio capture stopped")
    }

    // MARK: - Audio Buffer Management

    private func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        // Get audio buffer list
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        var audioBufferListSize = MemoryLayout<AudioBufferList>.size

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            NSLog("[Shepherd Audio] Failed to get audio buffer: \(status)")
            return
        }

        // Convert to Float array
        let audioBuffer = audioBufferList.mBuffers
        let frameCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size

        guard let data = audioBuffer.mData else { return }

        let floatBuffer = data.assumingMemoryBound(to: Float.self)
        let floatArray = Array(UnsafeBufferPointer(start: floatBuffer, count: frameCount))

        // Calculate audio level for UI
        let level = floatArray.reduce(0) { max($0, abs($1)) }

        Task { @MainActor in
            self.audioLevel = level
        }

        // Add to buffer with VAD logic
        processWithVAD(floatArray)
    }

    private func processWithVAD(_ samples: [Float]) {
        let maxLevel = samples.reduce(0) { max($0, abs($1)) }

        bufferLock.lock()
        defer { bufferLock.unlock() }

        if maxLevel > silenceThreshold {
            // Voice detected - add to buffer
            audioBuffer.append(contentsOf: samples)
            silenceFrameCount = 0
        } else {
            // Silence detected
            if !audioBuffer.isEmpty {
                audioBuffer.append(contentsOf: samples)
                silenceFrameCount += samples.count

                // Check if silence duration exceeds threshold
                if silenceFrameCount >= silenceFramesForCut {
                    // Chunk is ready - send for transcription
                    let chunk = audioBuffer
                    audioBuffer.removeAll()
                    silenceFrameCount = 0

                    // Notify callback with audio chunk
                    if chunk.count > Int(targetSampleRate) * 1 {  // At least 1 second
                        NSLog("[Shepherd Audio] Audio chunk ready: \(chunk.count) samples (\(Double(chunk.count) / targetSampleRate)s)")
                        onAudioChunkReady?(chunk)
                    }
                }
            }
        }

        // Prevent buffer from growing too large (max 30 seconds)
        let maxBufferSize = Int(targetSampleRate) * 30
        if audioBuffer.count > maxBufferSize {
            audioBuffer.removeFirst(audioBuffer.count - maxBufferSize)
        }
    }

    // MARK: - Manual Flush

    func flushBuffer() -> [Float]? {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        guard audioBuffer.count > Int(targetSampleRate) * 1 else { return nil }

        let chunk = audioBuffer
        audioBuffer.removeAll()
        silenceFrameCount = 0

        return chunk
    }
}

// MARK: - SCStreamDelegate

extension AudioCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[Shepherd Audio] Stream stopped with error: \(error)")
        Task { @MainActor in
            self.isCapturing = false
        }
    }
}

// MARK: - SCStreamOutput

extension AudioCaptureManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        Task { @MainActor in
            self.processAudioSample(sampleBuffer)
        }
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case noDisplay
    case captureNotSupported
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display found for audio capture"
        case .captureNotSupported:
            return "Audio capture is not supported on this device"
        case .configurationFailed:
            return "Failed to configure audio capture"
        }
    }
}
