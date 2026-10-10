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
                    .fill(model.isRadioConnected ? Color.green : (model.isRunning ? Color.orange : Color.secondary))
                    .frame(width: 12, height: 12)
                Text(model.status)
                    .font(.headline)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }

            Form {
                Picker("Radio connection", selection: $model.configuration.connectionKind) {
                    ForEach(AppConfiguration.ConnectionKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                if model.configuration.connectionKind == .local {
                    TextField("Radio host", text: $model.configuration.radioHost)
                }
                if model.configuration.connectionKind == .legacyXCAT {
                    HStack {
                        TextField("xCAT host", text: $model.configuration.legacyXCATHost)
                        TextField("xCAT CAT port", value: $model.configuration.legacyXCATPort, format: .number)
                            .frame(width: 160)
                    }
                    Toggle("Restart xCAT automatically if it crashes", isOn: $model.configuration.superviseLegacyXCAT)
                    Text("RUMlogNG → OM0RX-xCat → xCAT → SmartLink → FlexRadio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.configuration.connectionKind == .smartLink {
                    TextField("SmartLink email", text: $model.configuration.smartLinkEmail)
                        .textContentType(.username)
                    SecureField("SmartLink password (needed once)", text: $model.smartLinkPassword)
                        .textContentType(.password)
                    TextField("Preferred radio serial (optional)", text: $model.configuration.smartLinkRadioSerial)
                    Text("The password stays only in memory. SmartLink's refresh token and the radio certificate pin are protected by macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Forget Saved Session") { model.forgetSmartLinkSession() }
                        Button("Reset Radio Certificate Pin") { model.resetSmartLinkCertificatePin() }
                    }
                }
                if model.configuration.connectionKind != .legacyXCAT {
                    HStack {
                        TextField("Station", text: $model.configuration.stationName)
                        TextField("Slice", text: $model.configuration.sliceLetter)
                            .frame(width: 80)
                    }
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
