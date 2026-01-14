import SwiftUI
import UserNotifications

@main
struct ShepherdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @StateObject private var watcherManager = WatcherManager.shared

    init() {
        // Force initialization of managers
        _ = WatcherManager.shared
        _ = HotkeyManager.shared
        _ = OverlayWindowController.shared  // Initialize to start mark update timer
        NSLog("[Shepherd] App initialized")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(watcherManager)
        } label: {
            MenuBarIcon(state: appState.currentState)
        }
        .menuBarExtraStyle(.window)

        // Settings Window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App Delegate for Notifications
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Register notification categories with actions
        let acknowledgeAction = UNNotificationAction(
            identifier: "ACKNOWLEDGE_ACTION",
            title: "Acknowledge",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "SHEPHERD_ALERT",
            actions: [acknowledgeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])

        // Initialize OverlayWindowController to start the mark update timer
        _ = OverlayWindowController.shared
        NSLog("[Shepherd] AppDelegate initialized, mark timer should be running")
    }

    // Show notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        NSLog("[Shepherd] Notification will present: \(notification.request.content.body)")
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification actions
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        NSLog("[Shepherd] Notification action: \(response.actionIdentifier)")

        if response.actionIdentifier == "ACKNOWLEDGE_ACTION" ||
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                AppState.shared.acknowledgeAlert()
            }
        }

        completionHandler()
    }
}

// MARK: - Menu Bar Icon (Static)
struct MenuBarIcon: View {
    let state: ShepherdState

    @State private var isFlashing = false
    @State private var flashTimer: Timer?

    var body: some View {
        Group {
            if isMonitoring || isSelecting {
                // 监控中/选择中：黑色狗
                Image("MenuBarIconActive")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else if isTriggered {
                // 触发状态：黑色狗闪烁
                Image("MenuBarIconActive")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .opacity(isFlashing ? 0.3 : 1.0)
            } else {
                // 空闲状态：白色狗
                Image("MenuBarIconIdle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            }
        }
        .onAppear {
            updateFlashState()
        }
        .onChange(of: state) { _ in
            updateFlashState()
        }
        .onDisappear {
            stopFlashing()
        }
    }

    private var isTriggered: Bool {
        if case .triggered = state { return true }
        return false
    }

    private var isMonitoring: Bool {
        if case .monitoring = state { return true }
        return false
    }

    private var isSelecting: Bool {
        if case .selecting = state { return true }
        return false
    }

    private func updateFlashState() {
        stopFlashing()
        if isTriggered {
            flashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                isFlashing.toggle()
            }
            RunLoop.main.add(flashTimer!, forMode: .common)
        }
    }

    private func stopFlashing() {
        flashTimer?.invalidate()
        flashTimer = nil
        isFlashing = false
    }
}
