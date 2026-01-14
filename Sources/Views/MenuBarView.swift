import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()
                .padding(.vertical, 8)

            // Active Watchers
            if !appState.watchers.isEmpty {
                watchersSection
                Divider()
                    .padding(.vertical, 8)
            }

            // Actions
            actionsSection

            Divider()
                .padding(.vertical, 8)

            // Footer
            footerSection
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack {
            Image(systemName: "pawprint.fill")
                .font(.title2)
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Shepherd")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Speech processing indicator for audio watchers
                if hasAudioWatchers {
                    SpeechStatusIndicator()
                }
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }

    private var hasAudioWatchers: Bool {
        appState.watchers.contains { $0.watchMode == .audio && $0.isActive }
    }

    private var statusColor: Color {
        switch appState.currentState {
        case .idle:
            return .secondary
        case .selecting:
            return .kleinBlue
        case .monitoring:
            return .kleinBlue
        case .triggered:
            return .alertOrange
        }
    }

    private var statusText: String {
        switch appState.currentState {
        case .idle:
            return "No active watchers"
        case .selecting:
            return "Selecting region..."
        case .monitoring:
            return "\(appState.watchers.count) watcher(s) active"
        case .triggered(let id):
            if let watcher = appState.watchers.first(where: { $0.id == id }) {
                return "Alert: \(watcher.name)"
            }
            return "Alert triggered!"
        }
    }

    // MARK: - Watchers List
    private var watchersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active Watchers")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(appState.watchers) { watcher in
                WatcherRowView(watcher: watcher) {
                    appState.removeWatcher(watcher)
                }
            }
        }
    }

    // MARK: - Actions
    private var actionsSection: some View {
        VStack(spacing: 4) {
            Button(action: {
                appState.enterSelectionMode()
                OverlayWindowController.shared.show()
            }) {
                HStack {
                    Image(systemName: "plus.viewfinder")
                    Text("New Watcher")
                    Spacer()
                    Text("⌘⇧S")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
        }
    }

    // MARK: - Footer
    private var footerSection: some View {
        HStack {
            Button {
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Watcher Row
struct WatcherRowView: View {
    let watcher: Watcher
    let onDelete: () -> Void
    @EnvironmentObject var appState: AppState
    @StateObject private var audioCaptureManager = AudioCaptureManager.shared

    @State private var isHovering = false

    private var isTriggered: Bool {
        if case .triggered(let id) = appState.currentState {
            return id == watcher.id
        }
        return false
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                // Icon based on watch mode
                Image(systemName: watcher.watchMode == .audio ? "ear.fill" : "eye.fill")
                    .font(.caption)
                    .foregroundColor(isTriggered ? .alertOrange : (watcher.isActive ? .kleinBlue : .secondary))

                VStack(alignment: .leading, spacing: 1) {
                    Text(watcher.name)
                        .font(.caption)
                        .lineLimit(1)

                    if let keyword = watcher.keyword, !keyword.isEmpty {
                        Text(watcher.watchMode == .audio ? "Listening: \(keyword)" : "Keyword: \(keyword)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isTriggered ? Color.alertOrange.opacity(0.15) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            .cornerRadius(4)

            // Action buttons for this specific watcher when triggered
            if isTriggered {
                HStack(spacing: 8) {
                    // Replay button for audio watchers
                    if watcher.watchMode == .audio {
                        Button(action: {
                            if audioCaptureManager.isPlayingReplay {
                                audioCaptureManager.stopReplay()
                            } else {
                                audioCaptureManager.playReplay()
                            }
                        }) {
                            HStack {
                                Image(systemName: audioCaptureManager.isPlayingReplay ? "stop.fill" : "gobackward.30")
                                Text(audioCaptureManager.isPlayingReplay ? "Stop" : "Replay 30s")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.kleinBlue.opacity(0.2))
                        .cornerRadius(4)
                    }

                    // Acknowledge button
                    Button(action: {
                        audioCaptureManager.stopReplay()
                        appState.acknowledgeAlert()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Acknowledge")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.alertOrange.opacity(0.2))
                    .cornerRadius(4)
                }
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Speech Status Indicator
struct SpeechStatusIndicator: View {
    @StateObject private var whisperManager = WhisperManager.shared

    var body: some View {
        HStack(spacing: 4) {
            // Animated indicator when processing
            if whisperManager.isProcessing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Processing speech...")
                    .font(.caption2)
                    .foregroundColor(.kleinBlue)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch whisperManager.modelState {
        case .ready:
            return .green
        case .loading:
            return .orange
        case .error:
            return .red
        case .notLoaded:
            return .gray
        }
    }

    private var statusText: String {
        switch whisperManager.modelState {
        case .ready:
            return "Speech ready"
        case .loading:
            return "Loading speech..."
        case .error:
            return "Speech unavailable"
        case .notLoaded:
            return "Speech not ready"
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
