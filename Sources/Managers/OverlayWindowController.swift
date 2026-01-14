import SwiftUI
import AppKit

// MARK: - Custom Window that accepts keyboard input
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayWindowController: ObservableObject {
    static let shared = OverlayWindowController()

    private var overlayWindows: [NSWindow] = []
    private var markWindows: [UUID: NSWindow] = [:]
    private var markUpdateTimer: Timer?
    private var lastPositions: [UUID: CGPoint] = [:]

    private init() {
        startMarkUpdateTimer()
    }

    private func startMarkUpdateTimer() {
        // Stop existing timer if any
        markUpdateTimer?.invalidate()

        // 20 FPS for smooth tracking (0.05s interval)
        markUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMarkPositions()
            }
        }
        // Ensure timer runs even during UI interactions
        RunLoop.main.add(markUpdateTimer!, forMode: .common)
        NSLog("[Shepherd] Mark update timer started")
    }

    private func updateMarkPositions() {
        let watchers = AppState.shared.watchers
        guard !watchers.isEmpty else { return }

        for watcher in watchers {
            // If mark window doesn't exist, create it
            if markWindows[watcher.id] == nil {
                showMark(for: watcher)
            }

            if let existingWindow = markWindows[watcher.id] {
                let region = watcher.currentRegion
                guard let screen = NSScreen.main else { continue }
                let screenHeight = screen.frame.height
                let size: CGFloat = 80

                let targetOrigin = CGPoint(
                    x: region.minX,
                    y: screenHeight - region.minY - size
                )

                // Get current position from lastPositions cache (more accurate than window.frame during animation)
                let lastPosition = lastPositions[watcher.id] ?? existingWindow.frame.origin
                let distance = hypot(targetOrigin.x - lastPosition.x, targetOrigin.y - lastPosition.y)

                // Only update if there's significant movement
                if distance > 2 {
                    // Use smooth interpolation: move 30% toward target each frame
                    let interpolationFactor: CGFloat = 0.3
                    let newOrigin = CGPoint(
                        x: lastPosition.x + (targetOrigin.x - lastPosition.x) * interpolationFactor,
                        y: lastPosition.y + (targetOrigin.y - lastPosition.y) * interpolationFactor
                    )

                    // Log when moving significantly (only once per big move to reduce spam)
                    if distance > 50 {
                        shepherdLog("Mark moving: '\(watcher.name)' distance=\(Int(distance))")
                    }

                    // Update window position directly (no animation conflicts)
                    existingWindow.setFrameOrigin(newOrigin)
                    lastPositions[watcher.id] = newOrigin
                } else if distance > 0.5 {
                    // Snap to final position for tiny movements
                    existingWindow.setFrameOrigin(targetOrigin)
                    lastPositions[watcher.id] = targetOrigin
                }
            }
        }
    }

    // MARK: - Show Overlay on All Screens
    func show() {
        hide() // Clear any existing windows

        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            overlayWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        // Activate the app to receive keyboard input
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true

        let overlayView = SelectionOverlayView()
            .environmentObject(AppState.shared)

        window.contentView = NSHostingView(rootView: overlayView)

        return window
    }

    // MARK: - Watcher Mark Windows
    func showMark(for watcher: Watcher) {
        let markWindow = createMarkWindow(for: watcher)
        markWindows[watcher.id] = markWindow
        markWindow.orderFront(nil)
    }

    func hideMark(for watcherId: UUID) {
        markWindows[watcherId]?.orderOut(nil)
        markWindows.removeValue(forKey: watcherId)
    }

    func updateAllMarks() {
        // Remove old marks
        for (id, window) in markWindows {
            if !AppState.shared.watchers.contains(where: { $0.id == id }) {
                window.orderOut(nil)
                markWindows.removeValue(forKey: id)
            }
        }

        // Add/update marks
        for watcher in AppState.shared.watchers {
            if markWindows[watcher.id] == nil {
                showMark(for: watcher)
            }
        }
    }

    private func createMarkWindow(for watcher: Watcher) -> NSWindow {
        // Larger size to accommodate the bigger pawprint with glow
        let size: CGFloat = 80

        // Convert from SwiftUI coordinates (top-left origin) to macOS screen coordinates (bottom-left origin)
        guard let screen = NSScreen.main else {
            fatalError("No main screen")
        }
        let screenHeight = screen.frame.height

        // Place mark at top-left of the region
        let origin = CGPoint(
            x: watcher.region.minX,
            y: screenHeight - watcher.region.minY - size
        )

        print("[Shepherd] Creating mark window at: \(origin) for region: \(watcher.region)")

        let window = NSWindow(
            contentRect: CGRect(origin: origin, size: CGSize(width: size, height: size)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false

        let markView = WatcherMarkView(watcherId: watcher.id)
            .environmentObject(AppState.shared)

        window.contentView = NSHostingView(rootView: markView)

        return window
    }
}
