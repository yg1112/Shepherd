import SwiftUI

struct SelectionOverlayView: View {
    @EnvironmentObject var appState: AppState

    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var mousePosition: CGPoint = .zero
    @State private var showInputPill: Bool = false
    @State private var isVisible: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background
                Color.overlayBackground
                    .opacity(isVisible ? 1 : 0)

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
                        onSubmit: { name, keyword in
                            appState.addWatcher(name: name, keyword: keyword)
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
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    mousePosition = location
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
                }
                dragCurrent = value.location
            }
            .onEnded { value in
                if let rect = selectionRect, rect.width > 20, rect.height > 20 {
                    appState.completeSelection(region: rect)
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
