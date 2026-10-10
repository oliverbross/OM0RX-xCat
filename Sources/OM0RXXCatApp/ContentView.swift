import SwiftUI
import XCatCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OM0RX-xCat")
                        .font(.largeTitle.bold())
                    Text("Reliable FlexRadio CAT and RigCtlD bridge")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(model.isRunning ? Color.green : Color.secondary)
                    .frame(width: 12, height: 12)
                Text(model.status)
                    .font(.headline)
            }

            Form {
                Picker("Radio connection", selection: $model.configuration.connectionKind) {
                    ForEach(AppConfiguration.ConnectionKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                TextField("Radio host", text: $model.configuration.radioHost)
                    .disabled(model.configuration.connectionKind != .local)
                if model.configuration.connectionKind == .smartLink {
                    Text("SmartLink requires a FlexRadio-issued OAuth client ID for OM0RX-xCat. LAN and simulator testing are available now.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    TextField("Station", text: $model.configuration.stationName)
                    TextField("Slice", text: $model.configuration.sliceLetter)
                        .frame(width: 80)
                }
                HStack {
                    TextField("CAT port", value: $model.configuration.catPort, format: .number)
                    TextField("RigCtlD port", value: $model.configuration.rigCtlPort, format: .number)
                }
                Toggle("Allow CAT transmit and CW commands", isOn: $model.configuration.allowCATTransmit)
                    .help("Leave this off until receive-only operation is verified. RX/unkey remains available.")
                Text("Test safely on 15002/14532 while the original xCAT owns 5002/4532. Change the ports only when replacing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Start protocol servers automatically", isOn: $model.configuration.launchServersAutomatically)
            }
            .formStyle(.grouped)
            .disabled(model.isRunning)

            HStack {
                Button("Save Settings") { model.save() }
                    .disabled(model.isRunning)
                Spacer()
                Button(model.isRunning ? "Stop" : "Start") {
                    model.isRunning ? model.stop() : model.start()
                }
                .keyboardShortcut(.defaultAction)
            }

            GroupBox("Activity") {
                ScrollView {
                    Text(model.events.suffix(80).joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 140)
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 600)
    }
}
