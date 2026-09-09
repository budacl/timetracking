import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section("YouTrack") {
                TextField("Server URL", text: $store.baseURL, prompt: Text("https://youtrack.example.com"))
                SecureField("Permanent token", text: $store.token)
                Text("Create a token in YouTrack: your avatar → Profile → Account Security → New token (scope: YouTrack). It is stored in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Work item type", text: $store.workTypeName, prompt: Text("Development"))
                Text("Matched by name against the project's time-tracking types. Leave empty to let YouTrack pick the default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Test connection") { test() }
                        .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("Connected") ? .green : .red)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Daily review") {
                DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
                Text("On working days (Czech holidays and weekends are skipped) a notification asks you to review the day. The review sheet also opens automatically if the app is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Notifications") {
                    switch store.notificationsAuthorized {
                    case .some(true): Label("Allowed", systemImage: "checkmark.circle").foregroundStyle(.green)
                    case .some(false): Label("Not allowed", systemImage: "xmark.circle").foregroundStyle(.red)
                    case .none: Text("Unknown").foregroundStyle(.secondary)
                    }
                }
                Button("Open Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                CzechCalendar.calendar.date(bySettingHour: store.notificationHour, minute: store.notificationMinute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let comps = CzechCalendar.calendar.dateComponents([.hour, .minute], from: date)
                store.notificationHour = comps.hour ?? 16
                store.notificationMinute = comps.minute ?? 0
            }
        )
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            testResult = await store.testConnection()
            testing = false
        }
    }
}
