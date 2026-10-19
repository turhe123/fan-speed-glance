import ServiceManagement
import SwiftUI

/// Settings window: title style, refresh rate, alert thresholds, notifications and launch at login.
struct SettingsView: View {
    @AppStorage(Prefs.titleStyle) private var titleStyle = "both"
    @AppStorage(Prefs.refreshInterval) private var refreshInterval = 2.0
    @AppStorage(Prefs.highThreshold) private var highThreshold = 90.0
    @AppStorage(Prefs.alertHigh) private var alertHigh = true
    @AppStorage(Prefs.alertStopped) private var alertStopped = true
    @AppStorage(Prefs.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(Prefs.loudAlerts) private var loudAlerts = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var notificationsDenied = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Display") {
                Picker("Menu bar title", selection: $titleStyle) {
                    Text("Highest RPM").tag("rpm")
                    Text("Fan glyph").tag("glyph")
                    Text("Both").tag("both")
                }
                Picker("Refresh every", selection: $refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
            }
            Section("Alerts") {
                Toggle("Send notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, on in
                        guard on else { return }
                        FanMonitor.requestAuthorization { granted in notificationsDenied = !granted }
                    }
                if notificationsDenied {
                    Text("Notifications are turned off for FanSpeedGlance. Enable them in System Settings › Notifications.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("Play a sound (loud alerts)", isOn: $loudAlerts).disabled(!notificationsEnabled)
                Toggle("Fan above threshold for 2 minutes", isOn: $alertHigh)
                LabeledContent("Threshold") {
                    HStack {
                        Slider(value: $highThreshold, in: 50...100, step: 5)
                        Text("\(Int(highThreshold))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(!alertHigh)
                Toggle("Fan stopped for 1 minute while thermal state is Fair or worse", isOn: $alertStopped)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text("FanSpeedGlance is a read-only monitor; it never changes fan speeds.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Support / Donate ❤️") { Support.openDonation() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
