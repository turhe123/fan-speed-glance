import AppKit
import Combine
import Foundation
import UserNotifications

/// Keys and defaults for persisted settings, shared by views and the monitor.
enum Prefs {
    static let titleStyle = "titleStyle"          // "rpm", "glyph" or "both"
    static let refreshInterval = "refreshInterval" // seconds: 1, 2 or 5
    static let highThreshold = "highThreshold"     // percent of max RPM
    static let alertHigh = "alertHigh"
    static let alertStopped = "alertStopped"
    static let notificationsEnabled = "notificationsEnabled"
    static let loudAlerts = "loudAlerts"

    static func register() {
        UserDefaults.standard.register(defaults: [
            titleStyle: "both", refreshInterval: 2.0, highThreshold: 90.0,
            alertHigh: true, alertStopped: true, notificationsEnabled: false, loudAlerts: false,
        ])
    }
}

/// A single timestamped RPM sample used for the sparkline.
struct Sample {
    let date: Date
    let rpm: Double
}

/// Live state for one fan: latest readings, history and alert bookkeeping.
struct Fan: Identifiable {
    let id: Int
    let name: String
    var current: Double = 0
    var minimum: Double = 0
    var maximum: Double = 0
    var history: [Sample] = []

    var percent: Double { maximum > 0 ? min(max(current / maximum, 0), 1) : 0 }
    var displayRPM: Int { Int((current / 10).rounded()) * 10 }

    var highAlert = AlertTracker(hold: 120)
    var stopAlert = AlertTracker(hold: 60)
}

/// Debounces one alert condition: the hold timer starts only after two consecutive
/// qualifying samples, and the alert fires once until the condition clears.
struct AlertTracker {
    let hold: TimeInterval
    private var streak = 0
    private var since: Date?
    private var notified = false

    init(hold: TimeInterval) { self.hold = hold }

    /// Feeds one sample; returns true exactly once when the alert should fire.
    mutating func update(active: Bool, now: Date) -> Bool {
        guard active else { streak = 0; since = nil; notified = false; return false }
        streak += 1
        if streak >= 2 && since == nil { since = now }
        guard let start = since, !notified, now.timeIntervalSince(start) >= hold else { return false }
        notified = true
        return true
    }
}

/// Polls the SMC for fan speeds, tracks thermal state, keeps history and fires alerts.
@MainActor
final class FanMonitor: ObservableObject {
    enum Status { case loading, unsupported, noFans, ok }

    @Published private(set) var fans: [Fan] = []
    @Published private(set) var status: Status = .loading
    @Published private(set) var thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// Set by the popover so polling can pause while nothing needs live data.
    var popoverOpen = false { didSet { reschedule() } }

    private var smc: SMCReader?
    private var timer: Timer?
    private var currentInterval: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private let historyWindow: TimeInterval = 600
    private let defaults = UserDefaults.standard

    var highestRPM: Int? { fans.map(\.displayRPM).max() }

    init() {
        Prefs.register()
        do {
            let reader = try SMCReader()
            smc = reader
            let count = Int((try? reader.readNumber("FNum")) ?? 0)
            fans = (0..<max(count, 0)).map { Fan(id: $0, name: Self.name(for: $0, of: count)) }
            status = fans.isEmpty ? .noFans : .ok
        } catch {
            status = .unsupported
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.thermal = ProcessInfo.processInfo.thermalState }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reschedule() }
        })
        sample()
        reschedule()
        if defaults.bool(forKey: Prefs.notificationsEnabled) { Self.requestAuthorization() }
    }

    private static func name(for index: Int, of count: Int) -> String {
        switch (count, index) {
        case (1, _): return "Fan"
        case (2, 0): return "Left"
        case (2, 1): return "Right"
        default: return "Fan \(index + 1)"
        }
    }

    /// Starts, restarts or stops the timer based on popover visibility, title style and alerts.
    func reschedule() {
        let titleIsStatic = defaults.string(forKey: Prefs.titleStyle) == "glyph"
        let alertsActive = defaults.bool(forKey: Prefs.notificationsEnabled)
            && (defaults.bool(forKey: Prefs.alertHigh) || defaults.bool(forKey: Prefs.alertStopped))
        let needed = status == .ok && (popoverOpen || !titleIsStatic || alertsActive)
        let interval = [1.0, 2.0, 5.0].contains(defaults.double(forKey: Prefs.refreshInterval))
            ? defaults.double(forKey: Prefs.refreshInterval) : 2.0

        guard needed else { timer?.invalidate(); timer = nil; return }
        if timer != nil && interval == currentInterval { return }
        timer?.invalidate()
        currentInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        if popoverOpen { sample() }
    }

    /// Reads every fan once, rejecting implausible values and keeping the previous reading instead.
    func sample() {
        guard let smc, status == .ok else { return }
        let now = Date()
        for i in fans.indices {
            func read(_ suffix: String) -> Double? {
                guard let v = try? smc.readNumber("F\(i)\(suffix)"), v.isFinite, v >= 0, v <= 20_000 else { return nil }
                return v
            }
            if let v = read("Ac") { fans[i].current = v }
            if let v = read("Mn") { fans[i].minimum = v }
            if let v = read("Mx") { fans[i].maximum = v }
            fans[i].history.append(Sample(date: now, rpm: fans[i].current))
            fans[i].history.removeAll { now.timeIntervalSince($0.date) > historyWindow }
            evaluateAlerts(for: i, at: now)
        }
    }

    private func evaluateAlerts(for i: Int, at now: Date) {
        let threshold = defaults.double(forKey: Prefs.highThreshold) / 100
        let fan = fans[i]
        let isHigh = defaults.bool(forKey: Prefs.alertHigh) && fan.maximum > 0 && fan.percent >= threshold
        let warm = thermal != .nominal
        let isStopped = defaults.bool(forKey: Prefs.alertStopped) && warm && fan.minimum > 0 && fan.current == 0

        if fans[i].highAlert.update(active: isHigh, now: now) {
            notify("\(fan.name) fan running high",
                   "Above \(Int(threshold * 100))% of its maximum (\(fan.displayRPM) RPM) for over two minutes.")
        }
        if fans[i].stopAlert.update(active: isStopped, now: now) {
            notify("\(fan.name) fan reads 0 RPM",
                   "The fan has not spun for a minute while the thermal state is \(thermal.label).")
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard defaults.bool(forKey: Prefs.notificationsEnabled) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if defaults.bool(forKey: Prefs.loudAlerts) { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Asks for notification permission; the system only prompts the first time.
    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }
}

extension ProcessInfo.ThermalState {
    /// Human readable name of the thermal state.
    var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
