import SwiftUI

struct WatcherMarkView: View {
    let watcherId: UUID
    @EnvironmentObject var appState: AppState

    @State private var breathingOpacity: Double = 0.8
    @State private var alertPulse: Bool = false

    private var watcher: Watcher? {
        appState.watchers.first { $0.id == watcherId }
    }

    private var isTriggered: Bool {
        if case .triggered(let id) = appState.currentState {
            return id == watcherId
        }
        return false
    }

    private var iconColor: Color {
        isTriggered ? .alertOrange : .kleinBlue
    }

    private var isAudioMode: Bool {
        watcher?.watchMode == .audio
    }

    var body: some View {
        // Custom logo with pearl white circle background
        ZStack {
            // Pearl white circle background for better visibility
            Circle()
                .fill(Color.pearlWhite)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            // Icon based on watch mode
            if isAudioMode {
                // Ear icon for audio mode
                Image(systemName: "ear.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(iconColor)
                    .opacity(isTriggered ? (alertPulse ? 0.6 : 1.0) : breathingOpacity)
            } else {
                // Custom dog silhouette logo for visual mode
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .foregroundColor(iconColor)
                    .opacity(isTriggered ? (alertPulse ? 0.6 : 1.0) : breathingOpacity)
            }
        }
        .shadow(color: iconColor.opacity(0.4), radius: 6)
        .onAppear {
            startBreathingAnimation()
        }
        .onChange(of: isTriggered) { triggered in
            if triggered {
                startAlertAnimation()
            } else {
                alertPulse = false
                startBreathingAnimation()
            }
        }
    }

    private func startBreathingAnimation() {
        withAnimation(ShepherdAnimation.breathingPulse) {
            breathingOpacity = 1.0
        }
    }

    private func startAlertAnimation() {
        withAnimation(ShepherdAnimation.alertPulse) {
            alertPulse.toggle()
        }
    }
}

#Preview {
    HStack(spacing: 40) {
        // Normal state
        ZStack {
            Circle()
                .fill(Color.pearlWhite)
                .frame(width: 44, height: 44)
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .foregroundColor(.kleinBlue)
        }
        .shadow(color: Color.kleinBlue.opacity(0.4), radius: 6)

        // Triggered state
        ZStack {
            Circle()
                .fill(Color.pearlWhite)
                .frame(width: 44, height: 44)
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                .foregroundColor(.alertOrange)
        }
        .shadow(color: Color.alertOrange.opacity(0.4), radius: 6)
    }
    .padding(40)
    .background(Color.black)  // Dark background to test visibility
}
