import SwiftUI

// MARK: - Brand Colors
extension Color {
    /// International Klein Blue - Monitoring state
    static let kleinBlue = Color(hex: "#002FA7")

    /// Alert Orange - Triggered state
    static let alertOrange = Color(hex: "#FF5722")

    /// Overlay background
    static let overlayBackground = Color.black.opacity(0.3)
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Animation Constants
struct ShepherdAnimation {
    static let overlayFade = Animation.easeInOut(duration: 0.2)
    static let springBounce = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let colorTransition = Animation.easeInOut(duration: 0.5)
    static let breathingPulse = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
    static let alertPulse = Animation.easeInOut(duration: 0.3).repeatForever(autoreverses: true)
}

// MARK: - Layout Constants
struct ShepherdLayout {
    static let inputPillCornerRadius: CGFloat = 20
    static let markSize: CGFloat = 24
    static let markPadding: CGFloat = 8
    static let selectionStrokeWidth: CGFloat = 2
    static let selectionGlowRadius: CGFloat = 6
}

// MARK: - Timing Constants
struct ShepherdTiming {
    static let defaultCaptureInterval: TimeInterval = 3.0
    static let deadmanSwitchTimeout: TimeInterval = 300.0 // 5 minutes
}
