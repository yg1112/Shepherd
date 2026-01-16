import SwiftUI

struct SelectionOverlayView: View {
    @EnvironmentObject var appState: AppState

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var mousePosition: CGPoint = .zero
    @State private var showInputPill: Bool = false
    @State private var isVisible: Bool = false
    @State private var detectedWindowInfo: (windowID: CGWindowID, frame: CGRect, title: String?, ownerName: String?)? = nil

    // Smart Snap state
    @State private var snappedElementFrame: CGRect? = nil
    @State private var isSnapping: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background
                Color.overlayBackground
                    .opacity(isVisible ? 1 : 0)

                // Window highlight (Klein Blue border around detected window)
                if let windowInfo = detectedWindowInfo, !showInputPill, dragStart == nil {
                    WindowHighlightView(
                        frame: windowInfo.frame,
                        windowName: windowInfo.ownerName ?? "Window",
                        hasSnapElement: snappedElementFrame != nil
                    )
                }

                // Smart Snap highlight (magnetic element detection)
                if let snapFrame = snappedElementFrame, !showInputPill, dragStart == nil {
                    SmartSnapHighlightView(frame: snapFrame, isActive: isSnapping)
                }

                // Selection rectangle
                if let rect = selectionRect {
                    SelectionRectangleView(rect: rect)
                }

                // Custom cursor (Klein Blue crosshair)
                if !showInputPill {
                    CrosshairCursor()
                        .position(mousePosition)
                }

                // Input pill after selection
                if showInputPill, let rect = selectionRect {
                    InputPillView(
                        position: CGPoint(
                            x: rect.midX,
                            y: rect.maxY + 60
                        ),
                        windowName: detectedWindowInfo?.ownerName,
                        onSubmit: { name, keyword, watchMode in
                            appState.addWatcher(name: name, keyword: keyword, watchMode: watchMode)
                            OverlayWindowController.shared.hide()
                            OverlayWindowController.shared.updateAllMarks()
                        },
                        onCancel: {
                            showInputPill = false
                            appState.exitSelectionMode()
                            OverlayWindowController.shared.hide()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onTapGesture {
                // Smart Snap: single click to select snapped element
                handleSnapClick()
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    mousePosition = location

                    // Smart Snap: detect UI element under cursor
                    updateSmartSnap(at: location)

                    // Only update window info when we find a new window (don't clear it)
                    if let newWindow = WindowTracker.getWindowAt(point: location) {
                        if detectedWindowInfo?.windowID != newWindow.windowID {
                            shepherdLog("Window detected: '\(newWindow.ownerName ?? "Unknown")' ID:\(newWindow.windowID) frame:\(newWindow.frame)")
                        }
                        detectedWindowInfo = newWindow
                    }
                case .ended:
                    break
                }
            }
            .onAppear {
                withAnimation(ShepherdAnimation.overlayFade) {
                    isVisible = true
                }
            }
            .onExitCommand {
                appState.exitSelectionMode()
                OverlayWindowController.shared.hide()
            }
        }
    }

    // MARK: - Selection Rectangle
    private var selectionRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else {
            if let pending = appState.pendingRegion {
                return pending
            }
            return nil
        }

        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    // MARK: - Drag Gesture
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                    // Clear snap when starting to drag
                    snappedElementFrame = nil
                    isSnapping = false
                }
                dragCurrent = value.location
            }
            .onEnded { value in
                if let rect = selectionRect, rect.width > 20, rect.height > 20 {
                    appState.completeSelection(region: rect, windowInfo: detectedWindowInfo)
                    withAnimation(ShepherdAnimation.springBounce) {
                        showInputPill = true
                    }
                } else {
                    // Selection too small, cancel
                    dragStart = nil
                    dragCurrent = nil
                }
            }
    }

    // MARK: - Smart Snap

    /// Update smart snap detection at cursor position
    private func updateSmartSnap(at point: CGPoint) {
        guard NSScreen.main != nil else { return }
        let screenPoint = CGPoint(x: point.x, y: point.y)

        // Throttle snap detection to reduce CPU usage
        Task { @MainActor in
            if let elementFrame = AccessibilityManager.shared.findSnappableElement(at: screenPoint) {
                // Only update if frame changed significantly
                if snappedElementFrame == nil ||
                   abs(elementFrame.minX - (snappedElementFrame?.minX ?? 0)) > 5 ||
                   abs(elementFrame.minY - (snappedElementFrame?.minY ?? 0)) > 5 {
                    withAnimation(.easeOut(duration: 0.15)) {
                        snappedElementFrame = elementFrame
                        isSnapping = true
                    }
                }
            } else {
                if snappedElementFrame != nil {
                    withAnimation(.easeOut(duration: 0.1)) {
                        isSnapping = false
                    }
                    // Delay clearing to allow fade out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !isSnapping {
                            snappedElementFrame = nil
                        }
                    }
                }
            }
        }
    }

    /// Handle single click to snap select or select entire window
    private func handleSnapClick() {
        // Priority 1: Select snapped UI element
        if let snapFrame = snappedElementFrame {
            shepherdLog("Selected snapped element: \(snapFrame)")
            appState.completeSelection(region: snapFrame, windowInfo: detectedWindowInfo)
            withAnimation(ShepherdAnimation.springBounce) {
                showInputPill = true
            }
            return
        }

        // Priority 2: Select entire detected window
        if let windowInfo = detectedWindowInfo {
            shepherdLog("Selected entire window: '\(windowInfo.ownerName ?? "Unknown")' frame: \(windowInfo.frame)")
            appState.completeSelection(region: windowInfo.frame, windowInfo: windowInfo)
            withAnimation(ShepherdAnimation.springBounce) {
                showInputPill = true
            }
        }
    }
}

// MARK: - Window Highlight View (Klein Blue border around detected window)
struct WindowHighlightView: View {
    let frame: CGRect
    let windowName: String
    let hasSnapElement: Bool

    var body: some View {
        ZStack {
            // Window border
            Rectangle()
                .stroke(Color.kleinBlue, lineWidth: 3)
                .shadow(color: .kleinBlue, radius: 8)
                .shadow(color: .kleinBlue.opacity(0.5), radius: 16)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            // Action hint at bottom of window
            VStack {
                Spacer()

                HStack(spacing: 16) {
                    // Click to monitor hint
                    HStack(spacing: 6) {
                        Image(systemName: "cursorarrow.click.2")
                            .font(.system(size: 12, weight: .medium))
                        Text("Click to monitor \(windowName)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.kleinBlue.opacity(0.9))
                    .cornerRadius(8)

                    // Drag for custom region hint
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 12, weight: .medium))
                        Text("Drag for custom region")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
                }
                .padding(.bottom, 20)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }
}

// MARK: - Smart Snap Highlight View (Magnetic element detection)
struct SmartSnapHighlightView: View {
    let frame: CGRect
    let isActive: Bool

    var body: some View {
        ZStack {
            // Glow effect
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.green.opacity(0.6), lineWidth: 2)
                .shadow(color: .green, radius: isActive ? 8 : 4)
                .shadow(color: .green.opacity(0.5), radius: isActive ? 12 : 6)

            // Inner highlight
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(isActive ? 0.15 : 0.05))

            // Snap indicator text
            if isActive {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "scope")
                            .font(.system(size: 10))
                        Text("Click to snap")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(4)
                    .offset(y: 20)
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .opacity(isActive ? 1 : 0.6)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Selection Rectangle View
struct SelectionRectangleView: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .stroke(Color.white, lineWidth: ShepherdLayout.selectionStrokeWidth)
            .shadow(color: .kleinBlue, radius: ShepherdLayout.selectionGlowRadius)
            .shadow(color: .kleinBlue.opacity(0.5), radius: ShepherdLayout.selectionGlowRadius * 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Crosshair Cursor
struct CrosshairCursor: View {
    var body: some View {
        ZStack {
            // Glow effect
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.kleinBlue)
                .shadow(color: .kleinBlue, radius: 8)
                .shadow(color: .kleinBlue.opacity(0.8), radius: 4)

            // Core crosshair
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white)
        }
    }
}

#Preview {
    SelectionOverlayView()
        .environmentObject(AppState.shared)
        .frame(width: 800, height: 600)
        .background(Color.gray)
}
