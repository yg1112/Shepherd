import SwiftUI

struct InputPillView: View {
    let position: CGPoint
    var windowName: String? = nil
    let onSubmit: (String, String?, WatchMode) -> Void
    let onCancel: () -> Void

    @State private var watcherName: String = ""
    @State private var keyword: String = ""
    @State private var watchMode: WatchMode = .visual
    @State private var isVisible: Bool = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Window binding indicator
            if let windowName = windowName {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(.kleinBlue)
                        .font(.caption2)
                    Text("Bound to \(windowName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)
            }

            // Watch Mode Toggle (v3.0)
            HStack(spacing: 8) {
                ForEach(WatchMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            watchMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.caption)
                            Text(mode.displayName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(watchMode == mode ? Color.kleinBlue : Color.clear)
                        .foregroundColor(watchMode == mode ? .white : .secondary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)

            // Name input
            HStack {
                Image(systemName: watchMode.icon)
                    .foregroundColor(.kleinBlue)
                    .font(.caption)

                TextField("Watcher name...", text: $watcherName)
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    .onSubmit {
                        submitIfValid()
                    }
            }

            Divider()

            // Keyword input (optional)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)

                TextField(watchMode == .audio ? "Keyword to listen for..." : "Keyword to watch (optional)", text: $keyword)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        submitIfValid()
                    }
            }

            // Audio mode hint
            if watchMode == .audio {
                Text("Listens to system audio for spoken keywords")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Action buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(action: submitIfValid) {
                    HStack(spacing: 4) {
                        Text("Create")
                        Image(systemName: "return")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.kleinBlue)
                .disabled(watcherName.isEmpty)
                .opacity(watcherName.isEmpty ? 0.5 : 1)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .cornerRadius(ShepherdLayout.inputPillCornerRadius)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .scaleEffect(isVisible ? 1 : 0.8)
        .opacity(isVisible ? 1 : 0)
        .position(position)
        .onAppear {
            withAnimation(ShepherdAnimation.springBounce) {
                isVisible = true
            }
            // Auto-focus with slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFocused = true
            }
        }
    }

    private func submitIfValid() {
        guard !watcherName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespaces)
        onSubmit(watcherName, trimmedKeyword.isEmpty ? nil : trimmedKeyword, watchMode)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        InputPillView(
            position: CGPoint(x: 200, y: 200),
            onSubmit: { name, keyword, watchMode in
                print("Created: \(name), keyword: \(keyword ?? "none"), mode: \(watchMode)")
            },
            onCancel: {
                print("Cancelled")
            }
        )
    }
    .frame(width: 400, height: 400)
}
