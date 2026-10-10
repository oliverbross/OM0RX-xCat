import AppKit
import SwiftUI
import XCatCore

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.status)
                .font(.system(.caption, design: .monospaced).bold())
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: true)

            if let station = model.remoteStationStatus {
                Divider()
                Text("\(station.kpaSummary) · \(station.katSummary)")
                Text("\(station.routeSummary) · \(station.alarmSummary)")
                if !station.inhibitors.isEmpty {
                    Text("Locked: \(station.inhibitors.joined(separator: "; "))")
                        .foregroundStyle(.orange)
                        .lineLimit(4)
                }
                HStack {
                    ForEach(RemoteStationAction.allCases, id: \.self) { action in
                        Button(action.rawValue.capitalized) { model.performRemoteStationAction(action) }
                            .disabled(!model.remoteActionAllowed(action))
                    }
                }
            }

            Divider()
            HStack {
                Button("Open OM0RX-xCat") { openWindow(id: "main") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(minWidth: 420)
    }
}
