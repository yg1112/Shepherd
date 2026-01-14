import Foundation
import Speech
import NaturalLanguage

/// Model loading state for UI indicator
enum SpeechModelState: String {
    case notLoaded = "Not Ready"
    case loading = "Loading..."
    case ready = "Ready"
    case error = "Error"
}

/// Manages speech-to-text transcription
/// Currently uses Apple Speech framework, with MLX Whisper integration planned
@MainActor
final class WhisperManager: ObservableObject {
    static let shared = WhisperManager()

    @Published var isTranscribing: Bool = false
    @Published var lastTranscription: String = ""
    @Published var modelState: SpeechModelState = .notLoaded
    @Published var isProcessing: Bool = false

    // Speech recognition (Apple's built-in)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Keyword detection callback
    var onKeywordDetected: ((String, String) -> Void)?  // (keyword, fullText)

    private init() {
        requestSpeechAuthorization()
    }

    // MARK: - Authorization

    private func requestSpeechAuthorization() {
        modelState = .loading
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    NSLog("[Shepherd Whisper] Speech recognition authorized")
                    self.modelState = .ready
                case .denied:
                    NSLog("[Shepherd Whisper] Speech recognition denied")
                    self.modelState = .error
                case .restricted:
                    NSLog("[Shepherd Whisper] Speech recognition restricted")
                    self.modelState = .error
                case .notDetermined:
                    NSLog("[Shepherd Whisper] Speech recognition not determined")
                    self.modelState = .notLoaded
                @unknown default:
                    self.modelState = .error
                }
            }
        }
    }

    // MARK: - Transcription

    /// Transcribe audio samples and check for keywords
    func transcribeAndCheckKeywords(_ audioSamples: [Float], keywords: [String]) async -> (text: String, matchedKeyword: String?) {
        NSLog("[Shepherd Whisper] Transcribing \(audioSamples.count) samples...")

        isProcessing = true
        defer { isProcessing = false }

        // Convert Float array to audio buffer
        let text = await transcribeAudioSamples(audioSamples)

        guard !text.isEmpty else {
            return ("", nil)
        }

        lastTranscription = text
        NSLog("[Shepherd Whisper] Transcription: '\(text)'")

        // Check for keywords (case-insensitive)
        for keyword in keywords {
            if text.localizedCaseInsensitiveContains(keyword) {
                NSLog("[Shepherd Whisper] KEYWORD DETECTED: '\(keyword)' in '\(text)'")
                return (text, keyword)
            }
        }

        return (text, nil)
    }

    /// Transcribe audio samples using Apple Speech framework
    private func transcribeAudioSamples(_ samples: [Float]) async -> String {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            NSLog("[Shepherd Whisper] Speech recognizer not available")
            return ""
        }

        return await withCheckedContinuation { continuation in
            // Create audio buffer from samples
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
                continuation.resume(returning: "")
                return
            }

            buffer.frameLength = AVAudioFrameCount(samples.count)
            let channelData = buffer.floatChannelData![0]
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }

            // Create recognition request
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = false

            // Append buffer and end audio
            request.append(buffer)
            request.endAudio()

            // Start recognition
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error = error {
                    NSLog("[Shepherd Whisper] Recognition error: \(error)")
                    hasResumed = true
                    continuation.resume(returning: "")
                    return
                }

                if let result = result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Keyword Spotting (Simple)

    /// Simple keyword spotting using string matching
    func checkKeywords(in text: String, keywords: [String]) -> String? {
        let normalizedText = text.lowercased()

        for keyword in keywords {
            let normalizedKeyword = keyword.lowercased()

            // Exact substring match
            if normalizedText.contains(normalizedKeyword) {
                return keyword
            }

            // Fuzzy match using Levenshtein distance for similar words
            let words = normalizedText.split(separator: " ").map(String.init)
            for word in words {
                if levenshteinDistance(word, normalizedKeyword) <= 2 && normalizedKeyword.count > 3 {
                    return keyword
                }
            }
        }

        return nil
    }

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[m][n]
    }
}

// MARK: - MLX Whisper Integration (Future)

extension WhisperManager {
    /// Placeholder for MLX Whisper integration
    /// To use MLX Whisper:
    /// 1. Add mlx-swift package dependency
    /// 2. Download whisper-large-v3-turbo model
    /// 3. Implement MLX-based transcription

    func setupMLXWhisper() async throws {
        // TODO: Implement MLX Whisper setup
        // 1. Load model from mlx-community/whisper-large-v3-turbo
        // 2. Initialize MLX context
        // 3. Set up audio preprocessing pipeline

        NSLog("[Shepherd Whisper] MLX Whisper setup placeholder")
    }

    func transcribeWithMLX(_ audioSamples: [Float]) async -> String {
        // TODO: Implement MLX-based transcription
        // 1. Convert audio to MLXArray
        // 2. Run Whisper encoder
        // 3. Run Whisper decoder
        // 4. Return transcription

        NSLog("[Shepherd Whisper] MLX transcription placeholder")
        return ""
    }
}
