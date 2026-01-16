import SwiftUI
import Vision
import Combine
import UserNotifications
import os.log
import ImageIO
import UniformTypeIdentifiers
import AppKit

private let logger = Logger(subsystem: "com.shepherd.app", category: "WatcherManager")

@MainActor
final class WatcherManager: ObservableObject {
    static let shared = WatcherManager()

    private var captureTimer: Timer?
    private var previousFrames: [UUID: CGImage] = [:]
    private var unchangedDurations: [UUID: TimeInterval] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Audio monitoring (v3.0)
    private var isAudioMonitoringActive: Bool = false

    // Dynamic frame rate - reduce CPU when screen is static
    private var currentCaptureInterval: TimeInterval = 1.0
    private var consecutiveUnchangedFrames: Int = 0
    private let minCaptureInterval: TimeInterval = 0.5  // Fastest rate when changes detected
    private let maxCaptureInterval: TimeInterval = 5.0  // Slowest rate when static (1 FPS -> ~0.2 FPS)
    private let unchangedFramesBeforeSlowdown: Int = 3  // Start slowing after 3 unchanged frames

    private init() {
        setupNotifications()
        observeAppState()
        setupAudioCallback()
        logger.info("WatcherManager initialized")
        NSLog("[Shepherd] WatcherManager initialized")
    }

    // MARK: - Audio Callback Setup
    private func setupAudioCallback() {
        AudioCaptureManager.shared.onAudioChunkReady = { [weak self] samples in
            Task { @MainActor in
                await self?.processAudioChunk(samples)
            }
        }
    }

    private func processAudioChunk(_ samples: [Float]) async {
        // Get keywords from active audio watchers
        let audioWatchers = AppState.shared.watchers.filter { $0.isActive && $0.watchMode == .audio }
        guard !audioWatchers.isEmpty else { return }

        // Build flat list of all keywords (supporting comma-separated)
        var allKeywords: [String] = []
        var keywordToWatcher: [String: Watcher] = [:]

        for watcher in audioWatchers {
            guard let keywordString = watcher.keyword else { continue }
            let keywords = keywordString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for keyword in keywords where !keyword.isEmpty {
                allKeywords.append(keyword)
                keywordToWatcher[keyword.lowercased()] = watcher
            }
        }

        guard !allKeywords.isEmpty else { return }

        NSLog("[Shepherd] Processing audio chunk for keywords: \(allKeywords)")

        // Transcribe and check for keywords
        let result = await WhisperManager.shared.transcribeAndCheckKeywords(samples, keywords: allKeywords)

        if let matchedKeyword = result.matchedKeyword {
            // Find the watcher that matches this keyword
            if let watcher = keywordToWatcher[matchedKeyword.lowercased()] {
                NSLog("[Shepherd] AUDIO KEYWORD DETECTED: '\(matchedKeyword)' for watcher '\(watcher.name)'")
                triggerAlert(for: watcher, reason: "Heard keyword '\(matchedKeyword)' in audio")
            }
        }
    }

    // MARK: - Setup
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            shepherdLog("Notification permission requested: granted=\(granted), error=\(String(describing: error))")
        }

        // Check current notification settings
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            shepherdLog("Notification settings: authorizationStatus=\(settings.authorizationStatus.rawValue), alertSetting=\(settings.alertSetting.rawValue), soundSetting=\(settings.soundSetting.rawValue)")
        }
    }

    private func observeAppState() {
        AppState.shared.$watchers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] watchers in
                NSLog("[Shepherd] Watchers changed: \(watchers.count) watchers")
                if watchers.isEmpty {
                    self?.stopMonitoring()
                } else {
                    self?.updateMonitoringForWatchers(watchers)
                }
            }
            .store(in: &cancellables)
    }

    /// Dynamically update monitoring based on watcher types
    private func updateMonitoringForWatchers(_ watchers: [Watcher]) {
        let hasVisualWatchers = watchers.contains { $0.isActive && $0.watchMode == .visual }
        let hasAudioWatchers = watchers.contains { $0.isActive && $0.watchMode == .audio }

        // Handle visual monitoring with dynamic frame rate
        if hasVisualWatchers && captureTimer == nil {
            NSLog("[Shepherd] Starting visual monitoring with dynamic frame rate")
            currentCaptureInterval = minCaptureInterval
            consecutiveUnchangedFrames = 0
            Task { await captureAndAnalyze() }
            scheduleNextCapture()
        } else if !hasVisualWatchers && captureTimer != nil {
            NSLog("[Shepherd] Stopping visual monitoring (no visual watchers)")
            captureTimer?.invalidate()
            captureTimer = nil
            previousFrames.removeAll()
            unchangedDurations.removeAll()
            consecutiveUnchangedFrames = 0
        }

        // Handle audio monitoring - START only if audio watchers exist, STOP when none exist
        if hasAudioWatchers && !isAudioMonitoringActive {
            NSLog("[Shepherd] Starting audio monitoring")
            isAudioMonitoringActive = true
            Task {
                do {
                    try await AudioCaptureManager.shared.startCapture()
                } catch {
                    NSLog("[Shepherd] Failed to start audio capture: \(error)")
                    isAudioMonitoringActive = false
                }
            }
        } else if !hasAudioWatchers && isAudioMonitoringActive {
            NSLog("[Shepherd] Stopping audio monitoring (no audio watchers)")
            isAudioMonitoringActive = false
            Task {
                await AudioCaptureManager.shared.stopCapture()
            }
        }
    }

    // MARK: - Dynamic Frame Rate

    /// Schedule the next capture with dynamic interval
    private func scheduleNextCapture() {
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: currentCaptureInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.captureAndAnalyze()
                self?.scheduleNextCapture()
            }
        }
        RunLoop.main.add(captureTimer!, forMode: .common)
    }

    /// Adjust capture interval based on frame changes
    private func adjustCaptureInterval(frameChanged: Bool) {
        if frameChanged {
            // Content changed - reset to fast capture rate
            consecutiveUnchangedFrames = 0
            currentCaptureInterval = minCaptureInterval
            NSLog("[Shepherd] Frame changed - capture interval reset to \(currentCaptureInterval)s")
        } else {
            // No change - gradually slow down
            consecutiveUnchangedFrames += 1

            if consecutiveUnchangedFrames > unchangedFramesBeforeSlowdown {
                // Exponential backoff: double the interval each time, up to max
                let newInterval = min(currentCaptureInterval * 1.5, maxCaptureInterval)
                if newInterval != currentCaptureInterval {
                    currentCaptureInterval = newInterval
                    NSLog("[Shepherd] Static content - capture interval increased to \(String(format: "%.1f", currentCaptureInterval))s")
                }
            }
        }
    }

    // MARK: - Monitoring Loop
    func startMonitoring() {
        let watchers = AppState.shared.watchers
        guard !watchers.isEmpty else { return }
        updateMonitoringForWatchers(watchers)
    }

    func stopMonitoring() {
        NSLog("[Shepherd] Stopping monitoring")

        // Stop visual monitoring
        captureTimer?.invalidate()
        captureTimer = nil
        previousFrames.removeAll()
        unchangedDurations.removeAll()
        consecutiveUnchangedFrames = 0

        // Stop audio monitoring
        if isAudioMonitoringActive {
            isAudioMonitoringActive = false
            Task {
                await AudioCaptureManager.shared.stopCapture()
            }
        }
    }

    // MARK: - Capture & Analyze (Visual Mode Only)
    private func captureAndAnalyze() async {
        let visualWatchers = AppState.shared.watchers.filter { $0.isActive && $0.watchMode == .visual }
        shepherdLog("captureAndAnalyze called, visual watchers: \(visualWatchers.count)")

        var anyFrameChanged = false

        for watcher in visualWatchers {
            do {
                let regionToCapture = watcher.currentRegion
                let image = try await captureRegion(regionToCapture)

                // OCR Analysis - supports multiple comma-separated keywords
                if AppState.shared.enableOCR, let keywordString = watcher.keyword, !keywordString.isEmpty {
                    let text = await performOCR(on: image)

                    // Split by comma and check each keyword
                    let keywords = keywordString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    shepherdLog("OCR for '\(watcher.name)': keywords=\(keywords), found='\(text.prefix(100))'")

                    for keyword in keywords where !keyword.isEmpty {
                        if text.localizedCaseInsensitiveContains(keyword) {
                            shepherdLog("KEYWORD FOUND: '\(keyword)' in OCR text!")
                            triggerAlert(for: watcher, reason: "Keyword '\(keyword)' detected")
                            anyFrameChanged = true  // Important event - keep fast rate
                            break  // Stop checking after first match
                        }
                    }

                    if anyFrameChanged { continue }  // Skip frame comparison if keyword found
                }

                // Check for frame changes (for dynamic frame rate and deadman switch)
                if let previousFrame = previousFrames[watcher.id] {
                    let similarity = compareImages(image, previousFrame)
                    let frameChanged = similarity <= 0.99

                    if frameChanged {
                        anyFrameChanged = true
                        unchangedDurations[watcher.id] = 0
                    } else {
                        // Deadman Switch (pixel change detection)
                        if AppState.shared.enableDeadmanSwitch {
                            unchangedDurations[watcher.id, default: 0] += currentCaptureInterval
                            if unchangedDurations[watcher.id]! >= ShepherdTiming.deadmanSwitchTimeout {
                                triggerAlert(for: watcher, reason: "No change detected for 5 minutes")
                                unchangedDurations[watcher.id] = 0
                            }
                        }
                    }
                }
                previousFrames[watcher.id] = image
            } catch {
                NSLog("[Shepherd] ERROR: Capture failed for \(watcher.name): \(error)")
            }
        }

        // Adjust frame rate based on content changes
        adjustCaptureInterval(frameChanged: anyFrameChanged)
    }

    // MARK: - Screen Capture
    private func captureRegion(_ region: CGRect) async throws -> CGImage {
        // CGWindowListCreateImage uses top-left origin (same as SwiftUI)
        // No Y-flip needed!
        NSLog("[Shepherd] Capturing rect: \(region)")

        guard let image = CGWindowListCreateImage(
            region,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming]
        ) else {
            throw CaptureError.captureFailure
        }

        return image
    }

    // MARK: - OCR
    private func performOCR(on image: CGImage) async -> String {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    NSLog("[Shepherd] OCR error: \(error)")
                    continuation.resume(returning: "")
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Support Chinese and English
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("[Shepherd] OCR handler error: \(error)")
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Image Comparison
    private func compareImages(_ img1: CGImage, _ img2: CGImage) -> Double {
        guard img1.width == img2.width, img1.height == img2.height else {
            return 0
        }

        let size = img1.width * img1.height

        guard let data1 = img1.dataProvider?.data,
              let data2 = img2.dataProvider?.data else {
            return 0
        }

        let ptr1 = CFDataGetBytePtr(data1)
        let ptr2 = CFDataGetBytePtr(data2)

        var matchingPixels = 0
        let sampleRate = max(1, size / 10000)

        for i in stride(from: 0, to: size * 4, by: sampleRate * 4) {
            if ptr1?[i] == ptr2?[i] &&
               ptr1?[i+1] == ptr2?[i+1] &&
               ptr1?[i+2] == ptr2?[i+2] {
                matchingPixels += 1
            }
        }

        return Double(matchingPixels) / Double(size / sampleRate)
    }

    // MARK: - Alert Trigger
    private func triggerAlert(for watcher: Watcher, reason: String) {
        shepherdLog("ALERT TRIGGERED: \(watcher.name) - \(reason)")

        AppState.shared.triggerWatcher(watcher.id)

        Task {
            var evidenceImage: CGImage? = nil
            var savedURL: URL? = nil

            // Only capture screenshot for visual mode watchers
            if watcher.watchMode == .visual {
                evidenceImage = await captureEvidenceScreenshot(for: watcher)
                savedURL = saveEvidenceImage(evidenceImage, for: watcher)
            }

            await MainActor.run {
                sendNotification(watcher: watcher, reason: reason, evidenceURL: savedURL)
                sendWebhook(watcher: watcher, reason: reason, evidenceImage: evidenceImage)
                OverlayWindowController.shared.updateAllMarks()
            }
        }
    }

    // MARK: - Evidence Capture
    private func captureEvidenceScreenshot(for watcher: Watcher) async -> CGImage? {
        let region = watcher.currentRegion
        NSLog("[Shepherd] Capturing evidence screenshot for region: \(region)")

        guard let image = CGWindowListCreateImage(
            region,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            NSLog("[Shepherd] Failed to capture evidence screenshot")
            return nil
        }

        NSLog("[Shepherd] Evidence captured: \(image.width)x\(image.height)")
        return image
    }

    private func saveEvidenceImage(_ image: CGImage?, for watcher: Watcher) -> URL? {
        guard let image = image else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let filename = "shepherd_evidence_\(watcher.id.uuidString)_\(Date().timeIntervalSince1970).png"
        let fileURL = tempDir.appendingPathComponent(filename)

        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            NSLog("[Shepherd] Failed to create image destination")
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)

        if CGImageDestinationFinalize(destination) {
            NSLog("[Shepherd] Evidence saved to: \(fileURL.path)")
            return fileURL
        }

        NSLog("[Shepherd] Failed to save evidence image")
        return nil
    }

    private func sendNotification(watcher: Watcher, reason: String, evidenceURL: URL?) {
        shepherdLog("Sending notification for watcher: \(watcher.name), reason: \(reason)")

        // Check notification settings before sending
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            shepherdLog("Before send - authStatus=\(settings.authorizationStatus.rawValue), alertSetting=\(settings.alertSetting.rawValue)")

            guard settings.authorizationStatus == .authorized else {
                shepherdLog("ERROR: Notifications not authorized! Status: \(settings.authorizationStatus.rawValue)")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Shepherd Alert"
            content.body = "\(watcher.name): \(reason)"
            content.sound = .default
            content.categoryIdentifier = "SHEPHERD_ALERT"
            content.interruptionLevel = .timeSensitive  // Make notification more prominent

            // Attach evidence screenshot if available
            if let evidenceURL = evidenceURL {
                do {
                    let attachment = try UNNotificationAttachment(
                        identifier: "evidence",
                        url: evidenceURL,
                        options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier]
                    )
                    content.attachments = [attachment]
                    shepherdLog("Evidence attached to notification")
                } catch {
                    shepherdLog("Failed to attach evidence: \(error)")
                }
            }

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    shepherdLog("Notification error: \(error)")
                } else {
                    shepherdLog("Notification sent successfully!")
                }
            }
        }
    }

    private func sendWebhook(watcher: Watcher, reason: String, evidenceImage: CGImage?) {
        guard !AppState.shared.webhookURL.isEmpty,
              let url = URL(string: AppState.shared.webhookURL) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "watcher_name": watcher.name,
            "watcher_id": watcher.id.uuidString,
            "reason": reason,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "region": [
                "x": watcher.region.origin.x,
                "y": watcher.region.origin.y,
                "width": watcher.region.width,
                "height": watcher.region.height
            ]
        ]

        // Add Base64 encoded evidence image
        if let image = evidenceImage {
            if let base64String = imageToBase64(image) {
                payload["evidence_image_base64"] = base64String
                NSLog("[Shepherd] Evidence image included in webhook (Base64)")
            }
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request).resume()
    }

    private func imageToBase64(_ image: CGImage) -> String? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }
}

// MARK: - Errors
enum CaptureError: Error {
    case noDisplay
    case captureFailure
}
