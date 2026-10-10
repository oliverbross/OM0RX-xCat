import AppKit
import SwiftUI
import XCatCore

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    let allowsUndocking: Bool
    let isDetached: Bool

    init(allowsUndocking: Bool = true, isDetached: Bool = false) {
        self.allowsUndocking = allowsUndocking
        self.isDetached = isDetached
    }

    private let cyan = Color(red: 0.40, green: 0.91, blue: 0.98)
    private let green = Color(red: 0.43, green: 0.91, blue: 0.72)
    private let amber = Color(red: 0.99, green: 0.79, blue: 0.39)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                header
                vfoStrip
                metrics
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                if let station = model.remoteStationStatus {
                    telemetryCard(
                        title: station.kpaDetailPrimary,
                        detail: station.kpaDetailSecondary,
                        tint: station.kpaSummary.contains("OPERATE") ? green : amber,
                        background: Color(red: 0.10, green: 0.14, blue: 0.24)
                    )
                    telemetryCard(
                        title: station.katDetailPrimary,
                        detail: station.katDetailSecondary,
                        tint: station.katSummary.contains("tuning") ? amber : cyan,
                        background: Color(red: 0.05, green: 0.19, blue: 0.22)
                    )
                    routeCard(station)
                    actionBar
                } else {
                    ContentUnavailableView(
                        "Waiting for station telemetry",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text(model.status)
                    )
                    .frame(height: 176)
                }
                PropagationConditionsView()
                footer(model.remoteStationStatus)
            }
            .frame(width: 548)
            .frame(maxHeight: .infinity, alignment: .top)
            Divider().overlay(cyan.opacity(0.18))
            RotatorMonitorPanel()
        }
        .frame(width: 979, height: 540, alignment: .top)
        .background(
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.06, blue: 0.11), Color(red: 0.02, green: 0.035, blue: 0.065)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background {
            if isDetached {
                DetachedWindowConfigurator()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.radioSnapshot?.frequencyHz, initial: true) { _, _ in
            let surface = isDetached ? "Monitor" : "Menu"
            DispatchQueue.main.async { model.noteTelemetryRendered(surface: surface) }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                headerFrequencies
                Text(headerDetail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(cyan.opacity(0.86))
                    .lineLimit(1)
            }
            Spacer()
            Text(connectionBadge)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(width: 138, height: 36)
                .background(badgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.03, green: 0.14, blue: 0.21))
    }

    private var headerFrequencies: some View {
        HStack(spacing: 14) {
            if let vfoA = model.radioSnapshot?.vfo("A") {
                headerFrequency(vfoA)
            }
            if let vfoB = model.radioSnapshot?.vfo("B") {
                headerFrequency(vfoB)
            }
            if model.radioSnapshot?.vfo("A") == nil, model.radioSnapshot?.vfo("B") == nil {
                Text(formatFrequency(model.radioSnapshot?.frequencyHz))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(cyan)
            }
        }
    }

    private func headerFrequency(_ vfo: RadioVFO) -> some View {
        Text("\(vfo.letter) \(formatCompactFrequency(vfo.frequencyHz))")
            .font(.system(
                size: model.radioSnapshot?.vfo("B") == nil ? 27 : 20,
                weight: vfo.isReceive ? .bold : .semibold,
                design: .rounded
            ))
            .monospacedDigit()
            .foregroundStyle(headerFrequencyColor(vfo))
            .lineLimit(1)
    }

    private func headerFrequencyColor(_ vfo: RadioVFO) -> Color {
        if model.radioSnapshot?.isTransmitting == true, vfo.isTransmit { return .red }
        return vfo.isReceive ? cyan : cyan.opacity(0.65)
    }

    private var vfoStrip: some View {
        HStack(spacing: 18) {
            Text(vfoText("A"))
            Text("|").foregroundStyle(.secondary)
            Text(vfoText("B"))
            Spacer()
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color(red: 0.58, green: 0.77, blue: 0.99))
        .padding(.horizontal, 16)
        .frame(height: 42)
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            MetricTile(
                title: "TX POWER",
                value: txPowerText,
                tint: Color(red: 1.0, green: 0.67, blue: 0.38),
                background: Color(red: 0.26, green: 0.14, blue: 0.08)
            )
            MetricTile(
                title: "SWR",
                value: swrText,
                tint: swrTint,
                background: Color(red: 0.05, green: 0.21, blue: 0.20)
            )
            MetricTile(
                title: "RF DRIVE",
                value: model.radioSnapshot?.rfPowerWatts.map { "\($0) W" } ?? "-- W",
                tint: Color(red: 0.82, green: 0.76, blue: 1.0),
                background: Color(red: 0.18, green: 0.13, blue: 0.31)
            )
        }
    }

    private func telemetryCard(title: String, detail: String, tint: Color, background: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(detail)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
        .padding(.horizontal, 14)
        .background(background)
    }

    private func routeCard(_ station: RemoteStationStatus) -> some View {
        HStack {
            Text(station.routeDetail.replacingOccurrences(of: "→", with: "›"))
            Spacer()
            Text(station.routeAlignment.uppercased())
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(station.routeAlignment.lowercased() == "confirmed" ? green : amber)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color(red: 0.05, green: 0.20, blue: 0.15))
    }

    private var actionBar: some View {
        HStack(spacing: 7) {
            if let action = model.amplifierToggleAction {
                Button(action.rawValue.capitalized) { model.performRemoteStationAction(action) }
                    .disabled(!model.remoteActionAllowed(action))
            }
            ForEach([RemoteStationAction.tune, .cancel], id: \.self) { action in
                Button(action.rawValue.capitalized) { model.performRemoteStationAction(action) }
                    .disabled(!model.remoteActionAllowed(action))
            }
            Spacer()
            if model.isRunning {
                Button("Reconnect") { model.reconnectRemoteAgent() }
                    .help("Re-establish HTTPS and WebSocket state without changing station state")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func footer(_ station: RemoteStationStatus?) -> some View {
        HStack(spacing: 8) {
            Text(footerText(station))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if allowsUndocking {
                Button("Undock Monitor") { openDetachedMonitor() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open this monitor as a separate movable window")
            }
            Button("Configure") { openMainWindow() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var headerDetail: String {
        let mode = model.radioSnapshot?.mode ?? "--"
        let station = model.remoteStationStatus
        return "\(mode) | \(station?.band ?? "--") | \(station?.routeAlignment ?? "unknown") | \(station?.interlockState ?? "--")"
    }

    private var connectionBadge: String {
        guard model.isRadioConnected else {
            return model.isRemoteAgentConnected ? "STALE" : "OFFLINE"
        }
        return model.radioSnapshot?.isTransmitting == true ? "TX" : "RX"
    }

    private var badgeColor: Color {
        guard model.isRadioConnected else {
            return model.isRemoteAgentConnected
                ? amber.opacity(0.72)
                : Color(red: 0.28, green: 0.33, blue: 0.41)
        }
        return model.radioSnapshot?.isTransmitting == true
            ? Color(red: 0.72, green: 0.11, blue: 0.11)
            : Color(red: 0.09, green: 0.40, blue: 0.20)
    }

    private var txPowerText: String {
        guard let watts = model.remoteStationStatus?.txPowerWatts else { return "--" }
        return String(format: "%.0f W", watts)
    }

    private var swrText: String {
        guard let station = model.remoteStationStatus, let swr = station.swr else { return "--" }
        return String(format: "%.2f %@", swr, station.swrIsLive ? "LIVE" : "LAST")
    }

    private var swrTint: Color {
        guard let swr = model.remoteStationStatus?.swr else { return .secondary }
        if swr >= 3 { return Color(red: 1.0, green: 0.64, blue: 0.64) }
        if swr >= 2 { return amber }
        return green
    }

    private func vfoText(_ letter: String) -> String {
        guard let vfo = model.radioSnapshot?.vfo(letter) else { return "VFO \(letter)  --" }
        return "VFO \(letter)  \(formatFrequency(vfo.frequencyHz))  \(vfo.mode)"
    }

    private func formatFrequency(_ frequencyHz: Int64?) -> String {
        guard let frequencyHz, frequencyHz > 0 else { return "--.---.--- MHz" }
        let mhz = frequencyHz / 1_000_000
        let khz = (frequencyHz % 1_000_000) / 1_000
        let hz = frequencyHz % 1_000
        return String(format: "%lld.%03lld.%03lld MHz", mhz, khz, hz)
    }

    private func formatCompactFrequency(_ frequencyHz: Int64) -> String {
        let mhz = frequencyHz / 1_000_000
        let khz = (frequencyHz % 1_000_000) / 1_000
        let hz = frequencyHz % 1_000
        return String(format: "%lld.%03lld.%03lld", mhz, khz, hz)
    }

    private func footerText(_ station: RemoteStationStatus?) -> String {
        let updated = model.lastSnapshotAt?.formatted(date: .omitted, time: .standard) ?? "--:--:--"
        let alarms = station?.alarmSummary.replacingOccurrences(of: "ALARM ", with: "") ?? "unknown"
        return "Updated \(updated) | alarms \(alarms) | commissioned \(station?.commissioned == true ? "True" : "False")"
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func openDetachedMonitor() {
        openWindow(id: "station-monitor")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct DetachedWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .normal
            window.isMovableByWindowBackground = true
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.setFrameAutosaveName("OM0RXStationMonitor")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let tint: Color
    let background: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
