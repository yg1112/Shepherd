import SwiftUI

struct InputPillView: View {
    let position: CGPoint
    let onSubmit: (String, String?) -> Void
    let onCancel: () -> Void

    @State private var watcherName: String = ""
    @State private var keyword: String = ""
    @State private var isVisible: Bool = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Name input
            HStack {
                Image(systemName: "pawprint.fill")
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

                TextField("Keyword to watch (optional)", text: $keyword)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        submitIfValid()
                    }
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
        onSubmit(watcherName, trimmedKeyword.isEmpty ? nil : trimmedKeyword)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        InputPillView(
            position: CGPoint(x: 200, y: 200),
            onSubmit: { name, keyword in
                print("Created: \(name), keyword: \(keyword ?? "none")")
            },
            onCancel: {
                print("Cancelled")
            }
        )
    }
    .frame(width: 400, height: 400)
}
