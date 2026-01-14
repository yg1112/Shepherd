import AppKit
import ApplicationServices

/// Accessibility Manager for Smart Snap functionality
/// Uses AXUIElement to detect UI elements under cursor for magnetic snapping
@MainActor
final class AccessibilityManager {
    static let shared = AccessibilityManager()

    private init() {}

    // MARK: - Permission Check

    /// Check if accessibility permission is granted
    static func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Request accessibility permission with prompt
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Element Detection

    /// Get the UI element frame at a given screen point
    /// Returns the bounding rect of the element if found
    func getElementFrame(at point: CGPoint) -> CGRect? {
        guard AccessibilityManager.isAccessibilityEnabled() else {
            return nil
        }

        // Get the element at the point
        let systemWide = AXUIElementCreateSystemWide()

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)

        guard result == .success, let element = element else {
            return nil
        }

        // Try to get the element's frame
        return getFrame(of: element)
    }

    /// Get frame of an AXUIElement
    private func getFrame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?

        // Get position
        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        guard posResult == .success, let posValue = position else {
            return nil
        }

        var point = CGPoint.zero
        if !AXValueGetValue(posValue as! AXValue, .cgPoint, &point) {
            return nil
        }

        // Get size
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
        guard sizeResult == .success, let sizeValue = size else {
            return nil
        }

        var sizeStruct = CGSize.zero
        if !AXValueGetValue(sizeValue as! AXValue, .cgSize, &sizeStruct) {
            return nil
        }

        return CGRect(origin: point, size: sizeStruct)
    }

    /// Get element info including role and title
    func getElementInfo(at point: CGPoint) -> ElementInfo? {
        guard AccessibilityManager.isAccessibilityEnabled() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)

        guard result == .success, let element = element else {
            return nil
        }

        // Get role
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "unknown"

        // Get title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String

        // Get description
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        let description = descRef as? String

        // Get frame
        let frame = getFrame(of: element)

        return ElementInfo(
            role: role,
            title: title,
            description: description,
            frame: frame
        )
    }

    /// Find the best snappable element at or near a point
    /// Prioritizes text fields, buttons, and other interactive elements
    func findSnappableElement(at point: CGPoint, searchRadius: CGFloat = 20) -> CGRect? {
        // First try exact point
        if let info = getElementInfo(at: point), let frame = info.frame {
            if isSnappableRole(info.role) {
                return frame
            }
        }

        // Try nearby points if exact hit misses
        let offsets: [(CGFloat, CGFloat)] = [
            (0, -searchRadius), (0, searchRadius),
            (-searchRadius, 0), (searchRadius, 0),
            (-searchRadius/2, -searchRadius/2), (searchRadius/2, -searchRadius/2),
            (-searchRadius/2, searchRadius/2), (searchRadius/2, searchRadius/2)
        ]

        for (dx, dy) in offsets {
            let testPoint = CGPoint(x: point.x + dx, y: point.y + dy)
            if let info = getElementInfo(at: testPoint), let frame = info.frame {
                if isSnappableRole(info.role) && frame.contains(point) {
                    return frame
                }
            }
        }

        // Fall back to any element at point
        return getElementFrame(at: point)
    }

    /// Check if an element role is worth snapping to
    private func isSnappableRole(_ role: String) -> Bool {
        let snappableRoles = [
            "AXButton",
            "AXTextField",
            "AXTextArea",
            "AXStaticText",
            "AXImage",
            "AXGroup",
            "AXList",
            "AXTable",
            "AXCell",
            "AXRow",
            "AXWindow",
            "AXScrollArea",
            "AXWebArea",
            "AXLink",
            "AXProgressIndicator",
            "AXSlider",
            "AXCheckBox",
            "AXRadioButton",
            "AXPopUpButton",
            "AXComboBox",
            "AXMenuButton"
        ]
        return snappableRoles.contains(role)
    }
}

// MARK: - Element Info

struct ElementInfo {
    let role: String
    let title: String?
    let description: String?
    let frame: CGRect?

    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        if let desc = description, !desc.isEmpty {
            return desc
        }
        return role.replacingOccurrences(of: "AX", with: "")
    }
}
