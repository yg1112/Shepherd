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

    private init() {}

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
