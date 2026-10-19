import SwiftUI

/// App entry point: a menu bar extra showing fan speeds plus a Settings window.
@main
struct FanSpeedGlanceApp: App {
    @StateObject private var monitor = FanMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// The status item title: highest RPM, a fan glyph, or both.
struct MenuBarLabel: View {
    @ObservedObject var monitor: FanMonitor
    @AppStorage(Prefs.titleStyle) private var titleStyle = "both"

    var body: some View {
        if let rpm = monitor.highestRPM, titleStyle != "glyph" {
            if titleStyle == "both" {
                Image(systemName: "fanblades.fill")
            }
            Text("\(rpm)").monospacedDigit()
        } else {
            Image(systemName: "fanblades.fill")
        }
    }
}

/// Opens the donation page in the default browser.
enum Support {
    static func openDonation() {
        if let url = URL(string: "https://ko-fi.com/leodavidai") {
            NSWorkspace.shared.open(url)
        }
    }
}
