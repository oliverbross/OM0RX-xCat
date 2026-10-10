import AppKit
import Combine
import Foundation
import XCatCore

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published private(set) var status = "Stopped"
    @Published private(set) var events: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isRadioConnected = false
    @Published var smartLinkPassword = ""
    @Published var remoteAgentToken = ""
    @Published private(set) var remoteStationStatus: RemoteStationStatus?
    @Published var remoteRITEnabled = false
    @Published var remoteRITOffsetHz = 0
    @Published var remoteXITEnabled = false
    @Published var remoteXITOffsetHz = 0
    @Published var remoteRFPowerWatts = 0

    private var catServer: TCPCommandServer?
    private var rigCtlServer: TCPCommandServer?
    private var radio: (any RadioControlling)?
    private var flexRadio: FlexRadioClient?
    private var smartLinkRadio: SmartLinkRadioClient?
    private var remoteAgent: RemoteAgentClient?
    private var legacyXCAT: LegacyXCATClient?
    private var lastLegacyXCATLaunch = Date.distantPast
    private var stopTask: Task<Void, Never>?

    var isStationReady: Bool {
        isRadioConnected
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "configuration"),
           let stored = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            configuration = stored
        } else {
            configuration = AppConfiguration(
                connectionKind: .simulator,
                catPort: 15_002,
                rigCtlPort: 14_532
            )
        }
    }

    func save() {
        do {
            try saveRemoteAgentTokenIfNeeded()
            persistConfiguration()
            record("Settings saved")
        } catch {
            record("Could not save settings: \(error.localizedDescription)")
        }
    }

    func forgetSmartLinkSession() {
        do {
            try SmartLinkKeychain(accountIdentifier: configuration.smartLinkEmail).deleteRefreshToken()
            record("Forgot the saved SmartLink session")
        } catch {
            record("Could not forget SmartLink session: \(error.localizedDescription)")
        }
    }

    func resetSmartLinkCertificatePin() {
        let serial = configuration.smartLinkRadioSerial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serial.isEmpty else {
            record("Connect once or enter a radio serial before resetting its certificate pin")
            return
        }
        do {
            try SmartLinkCertificatePinStore().delete(identity: serial)
            record("Reset the trusted certificate for radio \(serial)")
        } catch {
            record("Could not reset the trusted certificate: \(error.localizedDescription)")
        }
    }

    func forgetRemoteAgentToken() {
        do {
            try RemoteAgentKeychain(endpointIdentifier: configuration.remoteAgentBaseURL).deleteToken()
            remoteAgentToken = ""
            record("Forgot the saved Remote Agent token")
        } catch {
            record("Could not forget Remote Agent token: \(error.localizedDescription)")
        }
    }

    func start() {
        guard !isRunning, stopTask == nil else { return }
        do {
            let selectedRadio: any RadioControlling
            var initialRadioStatus: String?
            if configuration.connectionKind == .remoteAgent {
                let baseURL = configuration.remoteAgentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !baseURL.isEmpty else { throw XCatError.server("Enter the Remote Agent HTTPS URL.") }
                let keychain = RemoteAgentKeychain(endpointIdentifier: baseURL)
                let enteredToken = remoteAgentToken.trimmingCharacters(in: .whitespacesAndNewlines)
                let token = enteredToken.isEmpty ? (try keychain.loadToken() ?? "") : enteredToken
                let client = try RemoteAgentClient(
                    baseURL: baseURL,
                    token: token,
                    onState: { [weak self] state, description in
                        Task { @MainActor in
                            if state != .ready {
                                self?.isRadioConnected = false
                                self?.status = description
                            }
                            self?.record("Agent: \(description)")
                        }
                    },
                    onSnapshot: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.isRadioConnected = snapshot.isConnected
                            self?.remoteStationStatus = snapshot.remoteStationStatus
                            self?.status = Self.radioStatus(snapshot)
                        }
                    }
                )
                if !enteredToken.isEmpty { try keychain.saveToken(enteredToken) }
                remoteAgent = client
                selectedRadio = client
                remoteAgentToken = ""
            } else if configuration.connectionKind == .local {
                guard !configuration.radioHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw XCatError.server("Enter the local radio host or IP address.")
                }
                let client = FlexRadioClient(
                    host: configuration.radioHost,
                    port: configuration.radioPort,
                    stationName: configuration.stationName,
                    sliceLetter: configuration.sliceLetter,
                    onState: { [weak self] state, description in
                        Task { @MainActor in
                            if state != .ready {
                                self?.isRadioConnected = false
                                self?.status = description
                            }
                            self?.record("Radio: \(description)")
                        }
                    },
                    onSnapshot: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.isRadioConnected = snapshot.isConnected
                            if snapshot.isConnected { self?.status = Self.radioStatus(snapshot) }
                        }
                    }
                )
                flexRadio = client
                selectedRadio = client
            } else if configuration.connectionKind == .legacyXCAT {
                ensureLegacyXCATRunning()
                let client = LegacyXCATClient(
                    host: configuration.legacyXCATHost,
                    port: configuration.legacyXCATPort,
                    onState: { [weak self] state, description in
                        Task { @MainActor in
                            self?.status = description
                            if state != .ready { self?.isRadioConnected = false }
                            self?.record("Radio: \(description)")
                            if state == .retrying || state == .failed {
                                self?.ensureLegacyXCATRunning()
                            }
                        }
                    },
                    onSnapshot: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.isRadioConnected = snapshot.isConnected
                            if snapshot.isConnected {
                                self?.status = Self.radioStatus(snapshot)
                            }
                        }
                    }
                )
                legacyXCAT = client
                selectedRadio = client
            } else if configuration.connectionKind == .smartLink {
                guard !configuration.smartLinkEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw XCatError.server("Enter the SmartLink email address.")
                }
                let client = SmartLinkRadioClient(
                    email: configuration.smartLinkEmail,
                    password: smartLinkPassword,
                    preferredSerial: configuration.smartLinkRadioSerial,
                    stationName: configuration.stationName,
                    sliceLetter: configuration.sliceLetter,
                    onState: { [weak self] state, description in
                        Task { @MainActor in
                            if state != .ready {
                                self?.isRadioConnected = false
                                self?.status = description
                            }
                            self?.record("Radio: \(description)")
                        }
                    },
                    onSnapshot: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.isRadioConnected = snapshot.isConnected
                            if snapshot.isConnected { self?.status = Self.radioStatus(snapshot) }
                        }
                    },
                    onRadioSelected: { [weak self] radio in
                        Task { @MainActor in
                            guard let self else { return }
                            if self.configuration.smartLinkRadioSerial != radio.serial {
                                self.configuration.smartLinkRadioSerial = radio.serial
                                self.persistConfiguration()
                                self.record("Selected SmartLink radio \(radio.nickname) (\(radio.serial))")
                            }
                        }
                    }
                )
                smartLinkRadio = client
                selectedRadio = client
                smartLinkPassword = ""
            } else {
                let snapshot = RadioSnapshot(
                    frequencyHz: 14_074_000,
                    mode: "DIGU",
                    slice: configuration.sliceLetter,
                    station: configuration.stationName
                )
                initialRadioStatus = Self.radioStatus(snapshot)
                selectedRadio = SimulatedRadio(
                    snapshot: snapshot,
                    onSnapshot: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.isRadioConnected = snapshot.isConnected
                            self?.status = Self.radioStatus(snapshot)
                        }
                    }
                )
            }
            radio = selectedRadio
            let catProcessor = CATCommandProcessor(radio: selectedRadio, allowTransmit: configuration.allowCATTransmit)
            let rigCtlProcessor = RigCtlCommandProcessor(
                radio: selectedRadio,
                allowTransmit: configuration.allowCATTransmit
            )

            let cat = TCPCommandServer(
                label: "com.oliverbross.OM0RXXCat.cat",
                framing: .semicolon,
                handler: { command in await catProcessor.handle(command) },
                onDisconnect: {
                    try? await selectedRadio.clearCW()
                    try? await selectedRadio.setTransmit(false)
                },
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.record("CAT: \(event)")
                        if event.contains("failed") { self?.status = event }
                    }
                }
            )
            let rigCtl = TCPCommandServer(
                label: "com.oliverbross.OM0RXXCat.rigctl",
                framing: .newline,
                handler: { command in await rigCtlProcessor.handle(command) },
                onDisconnect: {
                    try? await selectedRadio.clearCW()
                    try? await selectedRadio.setTransmit(false)
                },
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.record("RigCtlD: \(event)")
                        if event.contains("failed") { self?.status = event }
                    }
                }
            )
            try cat.start(port: configuration.catPort)
            try rigCtl.start(port: configuration.rigCtlPort)
            catServer = cat
            rigCtlServer = rigCtl
            isRunning = true
            isRadioConnected = configuration.connectionKind == .simulator
            status = initialRadioStatus ?? "Connecting to radio"
            record("OM0RX-xCat started")
            if let flexRadio {
                Task { await flexRadio.start() }
            }
            if let legacyXCAT {
                Task { await legacyXCAT.start() }
            }
            if let smartLinkRadio {
                Task { await smartLinkRadio.start() }
            }
            if let remoteAgent {
                Task { await remoteAgent.start() }
            }
        } catch {
            let message = error.localizedDescription
            stop()
            status = message
            record("Start failed: \(message)")
        }
    }

    func stop() {
        guard stopTask == nil else { return }
        catServer?.stop()
        rigCtlServer?.stop()
        catServer = nil
        rigCtlServer = nil
        let radioToStop = radio
        let flexToStop = flexRadio
        let legacyToStop = legacyXCAT
        let smartLinkToStop = smartLinkRadio
        let remoteAgentToStop = remoteAgent
        flexRadio = nil
        legacyXCAT = nil
        smartLinkRadio = nil
        remoteAgent = nil
        radio = nil
        isRunning = false
        isRadioConnected = false
        remoteStationStatus = nil
        status = "Stopped"
        record("OM0RX-xCat stopped")
        stopTask = Task { [weak self] in
            try? await radioToStop?.clearCW()
            try? await radioToStop?.setTransmit(false)
            if let smartLinkToStop {
                await smartLinkToStop.stop()
            } else if let remoteAgentToStop {
                await remoteAgentToStop.stop()
            } else if let flexToStop {
                await flexToStop.stop()
            } else if let legacyToStop {
                await legacyToStop.stop()
            }
            self?.stopTask = nil
        }
    }

    func stopAndWait() async {
        stop()
        let activeStop = stopTask
        await activeStop?.value
    }

    func reconnectRemoteAgent() {
        guard isRunning, let remoteAgent else {
            record("Agent reconnect unavailable: Remote Agent is not running")
            return
        }
        isRadioConnected = false
        status = "Reconnecting to Remote Station Agent"
        record("Agent: Manual reconnect requested")
        Task { await remoteAgent.reconnectNow() }
    }

    func applyRemoteRIT() {
        runRemoteControl("RIT") { client in
            try await client.setRIT(enabled: self.remoteRITEnabled, offsetHz: self.remoteRITOffsetHz, vfo: nil)
        }
    }

    func applyRemoteXIT() {
        runRemoteControl("XIT") { client in
            try await client.setXIT(enabled: self.remoteXITEnabled, offsetHz: self.remoteXITOffsetHz, vfo: nil)
        }
    }

    func applyRemoteRFPower() {
        runRemoteControl("RF power") { client in
            try await client.setRFPower(self.remoteRFPowerWatts)
        }
    }

    func performRemoteStationAction(_ action: RemoteStationAction) {
        runRemoteControl("Station \(action.rawValue)") { client in
            try await client.performStationAction(action)
        }
    }

    func remoteActionAllowed(_ action: RemoteStationAction) -> Bool {
        guard isRunning, isRadioConnected,
              remoteStationStatus?.supportedCommands.contains("station_\(action.rawValue)") == true else {
            return false
        }
        if action == .standby || action == .cancel { return true }
        return configuration.allowCATTransmit
    }

    private func record(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        events.append("\(formatter.string(from: Date()))  \(message)")
        if events.count > 200 {
            events.removeFirst(events.count - 200)
        }
    }

    private func persistConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: "configuration")
        }
    }

    private func saveRemoteAgentTokenIfNeeded() throws {
        let token = remoteAgentToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuration.connectionKind == .remoteAgent, !token.isEmpty else { return }
        let baseURL = configuration.remoteAgentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else { throw XCatError.server("Enter the Remote Agent HTTPS URL first.") }
        try RemoteAgentKeychain(endpointIdentifier: baseURL).saveToken(token)
        remoteAgentToken = ""
    }

    private func runRemoteControl(
        _ label: String,
        operation: @escaping @Sendable (RemoteAgentClient) async throws -> Void
    ) {
        guard let remoteAgent else {
            record("\(label) unavailable: Remote Agent is not running")
            return
        }
        Task { [weak self] in
            do {
                try await operation(remoteAgent)
                await MainActor.run { self?.record("\(label) accepted by Remote Agent") }
            } catch {
                await MainActor.run { self?.record("\(label) rejected: \(error.localizedDescription)") }
            }
        }
    }

    private static func radioStatus(_ snapshot: RadioSnapshot) -> String {
        var lines = ["A", "B"].map { letter in
            guard let vfo = snapshot.vfo(letter) else { return "VFO \(letter) · inactive" }
            let frequency = String(format: "%.3f MHz", Double(vfo.frequencyHz) / 1_000_000)
            let roles = [vfo.isReceive ? "RX" : nil, vfo.isTransmit ? "TX" : nil]
                .compactMap { $0 }
                .joined(separator: "+")
            return "VFO \(letter) · \(roles.isEmpty ? "standby" : roles) · \(frequency) \(vfo.mode)"
        }
        if let station = snapshot.remoteStationStatus {
            lines[0] += " · \(station.kpaSummary) · \(station.katSummary)"
            lines[1] += " · \(station.routeSummary) · \(station.alarmSummary)"
        }
        return lines.joined(separator: "\n")
    }

    private func ensureLegacyXCATRunning() {
        guard configuration.connectionKind == .legacyXCAT,
              configuration.superviseLegacyXCAT,
              Date().timeIntervalSince(lastLegacyXCATLaunch) >= 5 else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "de.DL3LSM.xCAT")
        guard running.isEmpty else { return }
        lastLegacyXCATLaunch = Date()
        let applicationURL = URL(fileURLWithPath: "/Applications/xCAT.app")
        if NSWorkspace.shared.open(applicationURL) {
            record("Started legacy xCAT for SmartLink transport")
        } else {
            record("Could not start /Applications/xCAT.app")
        }
    }
}
