import SwiftUI
import Vision
import Combine
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.shepherd.app", category: "WatcherManager")

@MainActor
final class WatcherManager: ObservableObject {
    static let shared = WatcherManager()

    private var captureTimer: Timer?
    private var previousFrames: [UUID: CGImage] = [:]
    private var unchangedDurations: [UUID: TimeInterval] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupNotifications()
        observeAppState()
        logger.info("WatcherManager initialized")
        NSLog("[Shepherd] WatcherManager initialized")
    }

    // MARK: - Setup
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            NSLog("[Shepherd] Notification permission: \(granted), error: \(String(describing: error))")
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
                    self?.startMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Monitoring Loop
    func startMonitoring() {
        guard captureTimer == nil else {
            NSLog("[Shepherd] Timer already running")
            return
        }

        NSLog("[Shepherd] Starting monitoring with interval: \(AppState.shared.captureInterval)s")

        // Run immediately once
        Task {
            await captureAndAnalyze()
        }

        captureTimer = Timer.scheduledTimer(withTimeInterval: AppState.shared.captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.captureAndAnalyze()
            }
        }
        RunLoop.main.add(captureTimer!, forMode: .common)
    }

    func stopMonitoring() {
        NSLog("[Shepherd] Stopping monitoring")
        captureTimer?.invalidate()
        captureTimer = nil
        previousFrames.removeAll()
        unchangedDurations.removeAll()
    }

    // MARK: - Capture & Analyze
    private func captureAndAnalyze() async {
        NSLog("[Shepherd] captureAndAnalyze called, watchers: \(AppState.shared.watchers.count)")

        for watcher in AppState.shared.watchers where watcher.isActive {
            do {
                let regionToCapture = watcher.currentRegion
                NSLog("[Shepherd] Capturing region for '\(watcher.name)': \(regionToCapture)")
                let image = try await captureRegion(regionToCapture)
                NSLog("[Shepherd] Captured image: \(image.width)x\(image.height)")

                // OCR Analysis
                if AppState.shared.enableOCR, let keyword = watcher.keyword, !keyword.isEmpty {
                    let text = await performOCR(on: image)
                    NSLog("[Shepherd] OCR result for '\(watcher.name)': '\(text)'")

                    if text.localizedCaseInsensitiveContains(keyword) {
                        NSLog("[Shepherd] KEYWORD FOUND: '\(keyword)' in '\(text)'")
                        triggerAlert(for: watcher, reason: "Keyword '\(keyword)' detected")
                        continue
                    }
                }

                // Deadman Switch (pixel change detection)
                if AppState.shared.enableDeadmanSwitch {
                    if let previousFrame = previousFrames[watcher.id] {
                        let similarity = compareImages(image, previousFrame)
                        if similarity > 0.99 {
                            unchangedDurations[watcher.id, default: 0] += AppState.shared.captureInterval
                            if unchangedDurations[watcher.id]! >= ShepherdTiming.deadmanSwitchTimeout {
                                triggerAlert(for: watcher, reason: "No change detected for 5 minutes")
                                unchangedDurations[watcher.id] = 0
                            }
                        } else {
                            unchangedDurations[watcher.id] = 0
                        }
                    }
                    previousFrames[watcher.id] = image
                }
            } catch {
                NSLog("[Shepherd] ERROR: Capture failed for \(watcher.name): \(error)")
            }
        }
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
        NSLog("[Shepherd] ALERT TRIGGERED: \(watcher.name) - \(reason)")

        AppState.shared.triggerWatcher(watcher.id)

        sendNotification(watcher: watcher, reason: reason)
        sendWebhook(watcher: watcher, reason: reason)
        OverlayWindowController.shared.updateAllMarks()
    }

    private func sendNotification(watcher: Watcher, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Shepherd Alert"
        content.body = "\(watcher.name): \(reason)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[Shepherd] Notification error: \(error)")
            }
        }
    }

    private func sendWebhook(watcher: Watcher, reason: String) {
        guard !AppState.shared.webhookURL.isEmpty,
              let url = URL(string: AppState.shared.webhookURL) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
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

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request).resume()
    }
}

// MARK: - Errors
enum CaptureError: Error {
    case noDisplay
    case captureFailure
}
