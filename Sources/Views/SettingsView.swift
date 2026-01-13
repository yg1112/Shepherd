import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            WebhookSettingsView()
                .tabItem {
                    Label("Webhook", systemImage: "network")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
        .environmentObject(appState)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Capture Interval")
                    Spacer()
                    Picker("", selection: $appState.captureInterval) {
                        Text("1 second").tag(1.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                Toggle("Enable OCR Detection", isOn: $appState.enableOCR)

                Toggle("Enable Deadman Switch", isOn: $appState.enableDeadmanSwitch)
                Text("Alerts when no change detected for 5 minutes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Open Screen Recording Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                .buttonStyle(.link)

                Text("Shepherd requires Screen Recording permission to monitor regions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Webhook Settings
struct WebhookSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var testStatus: String = ""

    var body: some View {
        Form {
            Section {
                TextField("Webhook URL", text: $appState.webhookURL)
                    .textFieldStyle(.roundedBorder)

                Text("POST request with JSON payload on trigger")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("Test Webhook") {
                        testWebhook()
                    }
                    .disabled(appState.webhookURL.isEmpty)

                    if !testStatus.isEmpty {
                        Text(testStatus)
                            .font(.caption)
                            .foregroundColor(testStatus.contains("Success") ? .green : .red)
                    }
                }
            }

            Section("Payload Format") {
                Text("""
                {
                  "watcher_name": "...",
                  "watcher_id": "uuid",
                  "reason": "...",
                  "timestamp": "ISO8601",
                  "region": { x, y, width, height }
                }
                """)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func testWebhook() {
        guard let url = URL(string: appState.webhookURL) else {
            testStatus = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "test": true,
            "message": "Shepherd webhook test",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])

        testStatus = "Testing..."

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    testStatus = "Error: \(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse, http.statusCode < 300 {
                    testStatus = "Success (\(http.statusCode))"
                } else {
                    testStatus = "Failed"
                }
            }
        }.resume()
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 48))
                .foregroundColor(.kleinBlue)

            Text("Shepherd")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version 1.0.0 (MVP)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Screen region monitoring for macOS")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("Press ⌘⇧S to create a new watcher")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
