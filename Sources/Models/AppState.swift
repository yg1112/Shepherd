import SwiftUI
import Combine

// MARK: - Debug Logger
func shepherdLog(_ message: String) {
    NSLog("[Shepherd] %@", message)
    // Also write to file for debugging
    let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("shepherd_debug.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logLine = "[\(timestamp)] \(message)\n"
    if let data = logLine.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

// MARK: - App State Enum
enum ShepherdState: Equatable {
    case idle
    case selecting
    case monitoring
    case triggered(watcherId: UUID)
}

// MARK: - Watch Mode (v3.0)
enum WatchMode: String, Codable, CaseIterable {
    case visual = "visual"  // Screen capture + OCR
    case audio = "audio"    // System audio + Speech recognition

    var icon: String {
        switch self {
        case .visual: return "eye.fill"
        case .audio: return "ear.fill"
        }
    }

    var displayName: String {
        switch self {
        case .visual: return "Visual"
        case .audio: return "Audio"
        }
    }
}

// MARK: - Watcher Model (v3.0 - Window Sticky + Audio)
struct Watcher: Identifiable, Codable {
    let id: UUID
    var name: String

    // v2.0: Window binding for "sticky" behavior
    var targetWindowID: CGWindowID?
    var windowTitle: String?
    var windowOwnerName: String?
    var relativeRegion: CGRect
    var absoluteRegion: CGRect

    // v3.0: Watch mode (visual/audio)
    var watchMode: WatchMode

    var keyword: String?
    var isActive: Bool
    var createdAt: Date
    var lastTriggeredAt: Date?

    // Computed: Get current capture region (window-relative or absolute)
    var currentRegion: CGRect {
        if let windowID = targetWindowID,
           let windowFrame = WindowTracker.getWindowFrame(windowID: windowID) {
            return CGRect(
                x: windowFrame.origin.x + relativeRegion.origin.x,
                y: windowFrame.origin.y + relativeRegion.origin.y,
                width: relativeRegion.width,
                height: relativeRegion.height
            )
        }
        return absoluteRegion
    }

    // For backward compatibility
    var region: CGRect { currentRegion }

    init(name: String, region: CGRect, keyword: String? = nil,
         windowID: CGWindowID? = nil, windowTitle: String? = nil,
         windowOwnerName: String? = nil, relativeRegion: CGRect? = nil,
         watchMode: WatchMode = .visual) {
        self.id = UUID()
        self.name = name
        self.absoluteRegion = region
        self.keyword = keyword
        self.isActive = true
        self.createdAt = Date()
        self.lastTriggeredAt = nil
        self.targetWindowID = windowID
        self.windowTitle = windowTitle
        self.windowOwnerName = windowOwnerName
        self.relativeRegion = relativeRegion ?? region
        self.watchMode = watchMode
    }

    // Custom Codable
    enum CodingKeys: String, CodingKey {
        case id, name, keyword, isActive, createdAt, lastTriggeredAt
        case targetWindowID, windowTitle, windowOwnerName
        case relativeRegion, absoluteRegion, region
        case watchMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastTriggeredAt = try container.decodeIfPresent(Date.self, forKey: .lastTriggeredAt)

        if let windowIDValue = try container.decodeIfPresent(UInt32.self, forKey: .targetWindowID) {
            targetWindowID = CGWindowID(windowIDValue)
        } else {
            targetWindowID = nil
        }
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        windowOwnerName = try container.decodeIfPresent(String.self, forKey: .windowOwnerName)

        if let absRegion = try container.decodeIfPresent(CGRect.self, forKey: .absoluteRegion) {
            absoluteRegion = absRegion
            relativeRegion = try container.decodeIfPresent(CGRect.self, forKey: .relativeRegion) ?? absRegion
        } else if let legacyRegion = try container.decodeIfPresent(CGRect.self, forKey: .region) {
            absoluteRegion = legacyRegion
            relativeRegion = legacyRegion
        } else {
            absoluteRegion = .zero
            relativeRegion = .zero
        }

        // v3.0: Watch mode (default to visual for backward compatibility)
        watchMode = try container.decodeIfPresent(WatchMode.self, forKey: .watchMode) ?? .visual
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(keyword, forKey: .keyword)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastTriggeredAt, forKey: .lastTriggeredAt)
        if let windowID = targetWindowID {
            try container.encode(UInt32(windowID), forKey: .targetWindowID)
        }
        try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
        try container.encodeIfPresent(windowOwnerName, forKey: .windowOwnerName)
        try container.encode(relativeRegion, forKey: .relativeRegion)
        try container.encode(absoluteRegion, forKey: .absoluteRegion)
        try container.encode(watchMode, forKey: .watchMode)
    }
}

// MARK: - Window Tracker Utility
struct WindowTracker {
    static func getAllWindows() -> [[String: Any]] {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowList
    }

    static func getWindowAt(point: CGPoint) -> (windowID: CGWindowID, frame: CGRect, title: String?, ownerName: String?)? {
        let windows = getAllWindows()
        let screenWidth = NSScreen.main?.frame.width ?? 2560
        let screenHeight = NSScreen.main?.frame.height ?? 1440

        var bestMatch: (windowID: CGWindowID, frame: CGRect, title: String?, ownerName: String?)? = nil
        var smallestArea: CGFloat = .greatestFiniteMagnitude

        // Add tolerance for title bar and floating point precision
        let tolerance: CGFloat = 30.0

        for window in windows {
            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else { continue }

            let frame = CGRect(x: x, y: y, width: width, height: height)
            let ownerName = window[kCGWindowOwnerName as String] as? String
            let title = window[kCGWindowName as String] as? String

            if frame.width < 50 || frame.height < 50 { continue }
            if ownerName == "Shepherd" { continue }

            let isFullScreen = frame.width >= screenWidth && frame.height >= screenHeight - 50
            if isFullScreen { continue }

            // Expand frame by tolerance for hit testing (especially for title bar area)
            let expandedFrame = frame.insetBy(dx: -tolerance, dy: -tolerance)
            if expandedFrame.contains(point) {
                let area = frame.width * frame.height
                if area < smallestArea {
                    smallestArea = area
                    bestMatch = (windowID, frame, title, ownerName)
                }
            }
        }
        return bestMatch
    }

    static func getWindowFrame(windowID: CGWindowID) -> CGRect? {
        let windows = getAllWindows()
        for window in windows {
            guard let wID = window[kCGWindowNumber as String] as? CGWindowID,
                  wID == windowID,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else { continue }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        // Debug: Window not found
        NSLog("[Shepherd] WindowTracker: Window ID %d not found in %d windows", windowID, windows.count)
        return nil
    }
}

// MARK: - Global App State
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var currentState: ShepherdState = .idle
    @Published var watchers: [Watcher] = []
    @Published var pendingRegion: CGRect? = nil
    @Published var pendingWindowInfo: (windowID: CGWindowID, frame: CGRect, title: String?, ownerName: String?)? = nil
    @Published var isOverlayVisible: Bool = false

    @Published var captureInterval: TimeInterval = ShepherdTiming.defaultCaptureInterval
    @Published var webhookURL: String = ""
    @Published var enableOCR: Bool = true
    @Published var enableDeadmanSwitch: Bool = true

    private init() { loadWatchers() }

    func enterSelectionMode() {
        currentState = .selecting
        isOverlayVisible = true
    }

    func exitSelectionMode() {
        currentState = watchers.isEmpty ? .idle : .monitoring
        isOverlayVisible = false
        pendingRegion = nil
        pendingWindowInfo = nil
    }

    func completeSelection(region: CGRect, windowInfo: (windowID: CGWindowID, frame: CGRect, title: String?, ownerName: String?)? = nil) {
        pendingRegion = region
        pendingWindowInfo = windowInfo
    }

    func addWatcher(name: String, keyword: String?, watchMode: WatchMode = .visual) {
        guard let region = pendingRegion else { return }
        let effectiveKeyword = (keyword?.isEmpty ?? true) ? name : keyword

        var watcher: Watcher
        if let windowInfo = pendingWindowInfo {
            let relativeRegion = CGRect(
                x: region.origin.x - windowInfo.frame.origin.x,
                y: region.origin.y - windowInfo.frame.origin.y,
                width: region.width,
                height: region.height
            )
            watcher = Watcher(name: name, region: region, keyword: effectiveKeyword,
                              windowID: windowInfo.windowID, windowTitle: windowInfo.title,
                              windowOwnerName: windowInfo.ownerName, relativeRegion: relativeRegion,
                              watchMode: watchMode)
            shepherdLog("Adding STICKY \(watchMode.displayName) watcher: '\(name)' bound to '\(windowInfo.ownerName ?? "Unknown")' (ID: \(windowInfo.windowID))")
        } else {
            watcher = Watcher(name: name, region: region, keyword: effectiveKeyword, watchMode: watchMode)
            shepherdLog("Adding \(watchMode.displayName) watcher: '\(name)' at absolute position")
        }

        watchers.append(watcher)
        currentState = .monitoring
        isOverlayVisible = false
        pendingRegion = nil
        pendingWindowInfo = nil
        saveWatchers()
    }

    func removeWatcher(_ watcher: Watcher) {
        watchers.removeAll { $0.id == watcher.id }
        if watchers.isEmpty { currentState = .idle }
        saveWatchers()
        // Update marks to remove the deleted watcher's mark
        OverlayWindowController.shared.updateAllMarks()
    }

    func triggerWatcher(_ watcherId: UUID) {
        currentState = .triggered(watcherId: watcherId)
        if let index = watchers.firstIndex(where: { $0.id == watcherId }) {
            watchers[index].lastTriggeredAt = Date()
        }
    }

    func acknowledgeAlert() {
        currentState = watchers.isEmpty ? .idle : .monitoring
    }

    private var watchersFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shepherd").appendingPathComponent("watchers.json")
    }

    private func saveWatchers() {
        do {
            let directory = watchersFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(watchers)
            try data.write(to: watchersFileURL)
        } catch { print("Failed to save watchers: \(error)") }
    }

    private func loadWatchers() {
        do {
            let data = try Data(contentsOf: watchersFileURL)
            watchers = try JSONDecoder().decode([Watcher].self, from: data)
            if !watchers.isEmpty { currentState = .monitoring }
        } catch { watchers = [] }
    }
}
