import SwiftUI

@main
struct ShepherdApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var hotkeyManager = HotkeyManager.shared
    @StateObject private var watcherManager = WatcherManager.shared

    init() {
        // Force initialization of managers
        _ = WatcherManager.shared
        _ = HotkeyManager.shared
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

// MARK: - Menu Bar Icon
struct MenuBarIcon: View {
    let state: ShepherdState

    @State private var isAnimating = false
    @State private var scale: CGFloat = 1.0

    var iconColor: Color {
        switch state {
        case .idle:
            return .primary
        case .selecting:
            return .kleinBlue
        case .monitoring:
            return .kleinBlue
        case .triggered:
            return .alertOrange
        }
    }

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .foregroundColor(iconColor)
            .opacity(isTriggered ? (isAnimating ? 0.5 : 1.0) : 1.0)
            .scaleEffect(isMonitoring ? scale : 1.0)
            .animation(isTriggered ? ShepherdAnimation.alertPulse : .default, value: isAnimating)
            .onAppear {
                if isTriggered {
                    isAnimating = true
                }
                if isMonitoring {
                    startBreathingAnimation()
                }
            }
            .onChange(of: state) { newState in
                if case .triggered = newState {
                    isAnimating = true
                } else {
                    isAnimating = false
                }
                if case .monitoring = newState {
                    startBreathingAnimation()
                } else if case .idle = newState {
                    scale = 1.0
                }
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

    private func startBreathingAnimation() {
        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            scale = 1.15
        }
    }
}
