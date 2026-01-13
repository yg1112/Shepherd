import SwiftUI

struct WatcherMarkView: View {
    let watcherId: UUID
    @EnvironmentObject var appState: AppState

    @State private var breathingOpacity: Double = 0.8
    @State private var alertPulse: Bool = false

    private var isTriggered: Bool {
        if case .triggered(let id) = appState.currentState {
            return id == watcherId
        }
        return false
    }

    private var iconColor: Color {
        isTriggered ? .alertOrange : .kleinBlue
    }

    var body: some View {
        // Large solid pawprint with subtle single-layer glow
        Image(systemName: "pawprint.fill")
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(iconColor)
            .opacity(isTriggered ? (alertPulse ? 0.6 : 1.0) : breathingOpacity)
            // Single clean glow
            .shadow(color: iconColor.opacity(0.6), radius: 4)
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
        Image(systemName: "pawprint.fill")
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(.kleinBlue)
            .shadow(color: Color.kleinBlue.opacity(0.6), radius: 4)

        Image(systemName: "pawprint.fill")
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(.alertOrange)
            .shadow(color: Color.alertOrange.opacity(0.6), radius: 4)
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
