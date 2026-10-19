import SwiftUI

/// The popover: thermal state header, one row per fan (or an empty/unsupported message) and a footer.
struct ContentView: View {
    @ObservedObject var monitor: FanMonitor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThermalHeader(state: monitor.thermal)
            Divider()
            switch monitor.status {
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .unsupported:
                message("Fan sensors unavailable",
                        "FanSpeedGlance could not open the System Management Controller on this Mac, so fan speeds can't be shown.")
            case .noFans:
                message("This Mac has no fans", "It is cooled passively. The thermal state above still tells you when it is working hard.")
            case .ok:
                ForEach(monitor.fans) { FanRow(fan: $0) }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { monitor.popoverOpen = true }
        .onDisappear { monitor.popoverOpen = false }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("Support / Donate ❤️") { Support.openDonation() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

/// Shows the system thermal state with a colored dot.
struct ThermalHeader: View {
    let state: ProcessInfo.ThermalState

    private var color: Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text("Thermal state").foregroundStyle(.secondary)
            Spacer()
            Text(state.label).fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One fan: name, RPM, percent-of-max gauge and a ten minute sparkline.
struct FanRow: View {
    let fan: Fan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(fan.name).font(.headline)
                Spacer()
                Text("\(fan.displayRPM) RPM").monospacedDigit().font(.system(.body, design: .rounded))
                Text("\(Int((fan.percent * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
            Gauge(value: fan.percent) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(fan.percent > 0.85 ? .orange : .accentColor)
            Sparkline(samples: fan.history, ceiling: fan.maximum)
                .frame(height: 28)
            HStack {
                Text("Min \(Int(fan.minimum))").monospacedDigit()
                Spacer()
                Text("last 10 min")
                Spacer()
                Text("Max \(Int(fan.maximum))").monospacedDigit()
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Draws RPM history over the last ten minutes as a filled line.
struct Sparkline: View {
    let samples: [Sample]
    let ceiling: Double
    private let window: TimeInterval = 600

    var body: some View {
        GeometryReader { geo in
            let top = max(ceiling, samples.map(\.rpm).max() ?? 0, 1)
            let end = samples.last?.date ?? Date()
            let points = samples.map { s -> CGPoint in
                let x = geo.size.width * (1 - CGFloat(end.timeIntervalSince(s.date) / window))
                let y = geo.size.height * (1 - CGFloat(s.rpm / top))
                return CGPoint(x: x, y: y)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.08))
                if points.count > 1, let first = points.first, let last = points.last {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(Color.accentColor.opacity(0.18))
                    Path { p in p.addLines(points) }
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
        .accessibilityLabel("RPM history sparkline")
    }
}
