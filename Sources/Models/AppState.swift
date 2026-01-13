import SwiftUI
import Combine

// MARK: - App State Enum
enum ShepherdState: Equatable {
    case idle
    case selecting
    case monitoring
    case triggered(watcherId: UUID)
}

// MARK: - Watcher Model
struct Watcher: Identifiable, Codable {
    let id: UUID
    var name: String
    var region: CGRect
    var keyword: String?
    var isActive: Bool
    var createdAt: Date
    var lastTriggeredAt: Date?

    init(name: String, region: CGRect, keyword: String? = nil) {
        self.id = UUID()
        self.name = name
        self.region = region
        self.keyword = keyword
        self.isActive = true
        self.createdAt = Date()
        self.lastTriggeredAt = nil
    }
}

// MARK: - Global App State
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var currentState: ShepherdState = .idle
    @Published var watchers: [Watcher] = []
    @Published var pendingRegion: CGRect? = nil
    @Published var isOverlayVisible: Bool = false

    // Settings
    @Published var captureInterval: TimeInterval = ShepherdTiming.defaultCaptureInterval
    @Published var webhookURL: String = ""
    @Published var enableOCR: Bool = true
    @Published var enableDeadmanSwitch: Bool = true

    private init() {
        loadWatchers()
    }

    // MARK: - State Transitions
    func enterSelectionMode() {
        currentState = .selecting
        isOverlayVisible = true
    }

    func exitSelectionMode() {
        currentState = watchers.isEmpty ? .idle : .monitoring
        isOverlayVisible = false
        pendingRegion = nil
    }

    func completeSelection(region: CGRect) {
        pendingRegion = region
    }

    func addWatcher(name: String, keyword: String?) {
        guard let region = pendingRegion else { return }
        // If no keyword provided, use the watcher name as the keyword
        let effectiveKeyword = (keyword?.isEmpty ?? true) ? name : keyword
        let watcher = Watcher(name: name, region: region, keyword: effectiveKeyword)
        print("[Shepherd] Adding watcher: name='\(name)', keyword='\(effectiveKeyword ?? "nil")', region=\(region)")
        watchers.append(watcher)
        currentState = .monitoring
        isOverlayVisible = false
        pendingRegion = nil
        saveWatchers()
    }

    func removeWatcher(_ watcher: Watcher) {
        watchers.removeAll { $0.id == watcher.id }
        if watchers.isEmpty {
            currentState = .idle
        }
        saveWatchers()
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

    // MARK: - Persistence
    private var watchersFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shepherd")
            .appendingPathComponent("watchers.json")
    }

    private func saveWatchers() {
        do {
            let directory = watchersFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(watchers)
            try data.write(to: watchersFileURL)
        } catch {
            print("Failed to save watchers: \(error)")
        }
    }

    private func loadWatchers() {
        do {
            let data = try Data(contentsOf: watchersFileURL)
            watchers = try JSONDecoder().decode([Watcher].self, from: data)
            if !watchers.isEmpty {
                currentState = .monitoring
            }
        } catch {
            watchers = []
        }
    }
}
