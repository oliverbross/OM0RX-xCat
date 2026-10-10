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
    @Published private(set) var isRemoteAgentConnected = false
    @Published private(set) var radioSnapshot: RadioSnapshot?
    @Published private(set) var lastSnapshotAt: Date?
    @Published private(set) var telemetryLatencySummary = "Waiting for a frequency change"
    @Published var smartLinkPassword = ""
    @Published var remoteAgentToken = ""
    @Published private(set) var remoteStationStatus: RemoteStationStatus?
    @Published var remoteRITEnabled = false
    @Published var remoteRITOffsetHz = 0
    @Published var remoteXITEnabled = false
    @Published var remoteXITOffsetHz = 0
    @Published var remoteRFPowerWatts = 0
    @Published private(set) var spotBridgeStatus = "Stopped"
    @Published private(set) var spotsReceived = 0
    @Published private(set) var spotsForwarded = 0
    @Published private(set) var spotsRejected = 0
    @Published private(set) var lastSpotSummary = "No spots received"
    @Published var remoteConfiguration = RemoteStationConfiguration.placeholder
    @Published private(set) var remoteConfigurationLoaded = false
    @Published private(set) var remoteConfigurationStatus = "Connect to load station settings"
    @Published private(set) var remoteConfigurationBusy = false
    @Published private(set) var rotatorConnectionState = DCU1RotatorClient.State.stopped
    @Published private(set) var rotatorStatus = "Not connected"
    @Published private(set) var rotatorFeedStatus = "RUMlog feed stopped"
    @Published private(set) var rotatorAzimuth: Double?
    @Published private(set) var rotatorTargetBearing: Double?
    @Published private(set) var rotatorTargetLabel = "No target"
    @Published private(set) var rotatorTargetSource = "Enter a bearing, grid, or call"
    @Published private(set) var rotatorTargetBand = "Other"
    @Published private(set) var rotatorTargetCoordinate: GeoCoordinate?
    @Published private(set) var rotatorTargetDistanceKilometers: Double?
    @Published private(set) var rotatorIsMoving = false
    @Published private(set) var rotatorMotionDirection = ""
    @Published var rotatorTargetInput = ""

    private var catServer: TCPCommandServer?
    private var rigCtlServer: TCPCommandServer?
    private var logbookSpotReceiver: UDPSpotReceiver?
    private var contestSpotReceiver: UDPSpotReceiver?
    private var rotatorFeedReceiver: UDPSpotReceiver?
    private var rotatorClient: DCU1RotatorClient?
    private var radio: (any RadioControlling)?
    private var flexRadio: FlexRadioClient?
    private var smartLinkRadio: SmartLinkRadioClient?
    private var remoteAgent: RemoteAgentClient?
    private var legacyXCAT: LegacyXCATClient?
    private var lastLegacyXCATLaunch = Date.distantPast
    private var stopTask: Task<Void, Never>?
    private var spotCapabilityWarningShown = false
    private var lastSpotError = ""
    private var lastTimedFrequency: Int64?
    private var pendingTelemetryTiming: TelemetryTiming?
    private var lastRotatorAzimuth: Double?
    private var lastRotatorMovementAt = Date.distantPast
    private var activeRotatorTarget: Double?
    private var lastAutomaticRotatorCommand: (bearing: Double, date: Date)?

    private struct TelemetryTiming {
        let frequencyHz: Int64
        let receivedAt: Date
        let transportMilliseconds: Int?
        var renderMilliseconds: [String: Int] = [:]
    }

    var isStationReady: Bool {
        isRadioConnected
    }

    var amplifierToggleAction: RemoteStationAction? {
        remoteStationStatus?.kpaOperate.map { $0 ? .standby : .operate }
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
        if configuration.rotator.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let imported = RotatorConfiguration.importedRotorConfiguration() {
            configuration.rotator = imported
        }
    }

    var rotatorHomeCoordinate: GeoCoordinate? {
        MaidenheadLocator.coordinate(from: configuration.rotator.homeGrid)
    }

    var currentBand: String {
        if let band = remoteStationStatus?.band, !band.isEmpty, band != "--" { return Self.normalizedBand(band) }
        guard let frequency = radioSnapshot?.frequencyHz else { return "Other" }
        switch frequency {
        case 1_800_000..<2_100_000: return "160m"
        case 3_400_000..<4_100_000: return "80m"
        case 5_000_000..<5_500_000: return "60m"
        case 6_900_000..<7_400_000: return "40m"
        case 10_000_000..<10_200_000: return "30m"
        case 13_900_000..<14_500_000: return "20m"
        case 18_000_000..<18_300_000: return "17m"
        case 20_900_000..<21_600_000: return "15m"
        case 24_800_000..<25_100_000: return "12m"
        case 27_900_000..<30_000_000: return "10m"
        case 49_000_000..<55_000_000: return "6m"
        case 69_000_000..<71_000_000: return "4m"
        case 143_000_000..<149_000_000: return "2m"
        case 420_000_000..<451_000_000: return "70cm"
        default: return "Other"
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
                            self?.isRemoteAgentConnected = state == .ready
                            if state != .ready {
                                self?.isRadioConnected = false
                                self?.status = description
                            }
                            self?.record("Agent: \(description)")
                        }
                    },
                    onSnapshot: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.applyRemoteAgentSnapshot(snapshot)
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
                            self?.radioSnapshot = snapshot
                            self?.lastSnapshotAt = Date()
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
                            self?.radioSnapshot = snapshot
                            self?.lastSnapshotAt = Date()
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
                            self?.radioSnapshot = snapshot
                            self?.lastSnapshotAt = Date()
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
                            self?.radioSnapshot = snapshot
                            self?.lastSnapshotAt = Date()
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
                Task { [weak self] in
                    await remoteAgent.start()
                    await self?.loadRemoteConfiguration(using: remoteAgent)
                }
            }
            if configuration.spotBridge.enabled {
                try startSpotBridge(radio: selectedRadio)
            }
            startRotatorIfNeeded()
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
        logbookSpotReceiver?.stop()
        contestSpotReceiver?.stop()
        stopRotator()
        catServer = nil
        rigCtlServer = nil
        logbookSpotReceiver = nil
        contestSpotReceiver = nil
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
        isRemoteAgentConnected = false
        radioSnapshot = nil
        lastSnapshotAt = nil
        telemetryLatencySummary = "Waiting for a frequency change"
        lastTimedFrequency = nil
        pendingTelemetryTiming = nil
        remoteStationStatus = nil
        remoteConfigurationLoaded = false
        remoteConfigurationStatus = "Connect to load station settings"
        remoteConfigurationBusy = false
        spotBridgeStatus = "Stopped"
        spotCapabilityWarningShown = false
        lastSpotError = ""
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

    func noteTelemetryRendered(surface: String) {
        guard configuration.connectionKind == .remoteAgent,
              let frequencyHz = radioSnapshot?.frequencyHz,
              var timing = pendingTelemetryTiming,
              timing.frequencyHz == frequencyHz,
              timing.renderMilliseconds[surface] == nil else { return }
        let isFirstRender = timing.renderMilliseconds.isEmpty
        timing.renderMilliseconds[surface] = max(0, Int(Date().timeIntervalSince(timing.receivedAt) * 1_000))
        pendingTelemetryTiming = timing
        telemetryLatencySummary = Self.latencySummary(timing)
        if isFirstRender {
            record("Latency \(surface): \(telemetryLatencySummary)")
        }
    }

    func restartSpotBridge() {
        save()
        logbookSpotReceiver?.stop()
        contestSpotReceiver?.stop()
        logbookSpotReceiver = nil
        contestSpotReceiver = nil
        guard configuration.spotBridge.enabled else {
            spotBridgeStatus = "Disabled"
            record("Spots: bridge disabled")
            return
        }
        guard isRunning, let radio else {
            spotBridgeStatus = "Starts with OM0RX-xCat"
            return
        }
        do {
            try startSpotBridge(radio: radio)
        } catch {
            spotBridgeStatus = "Listener error"
            record("Spots: \(error.localizedDescription)")
        }
    }

    func startRotatorIfNeeded() {
        guard configuration.rotator.enabled, configuration.rotator.connectAtLaunch else { return }
        startRotator()
    }

    func startRotator() {
        guard rotatorClient == nil else { return }
        let settings = configuration.rotator
        guard settings.enabled else {
            rotatorStatus = "Disabled in Rotator settings"
            return
        }
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            rotatorConnectionState = .failed
            rotatorStatus = "Enter the rotator TCP host"
            return
        }

        let client = DCU1RotatorClient(
            host: host,
            port: settings.port,
            pollMilliseconds: settings.pollIntervalMilliseconds,
            onState: { [weak self] state, detail in
                Task { @MainActor in
                    self?.rotatorConnectionState = state
                    self?.rotatorStatus = detail
                    if state != .connected { self?.rotatorIsMoving = false }
                }
            },
            onAzimuth: { [weak self] azimuth in
                Task { @MainActor in self?.applyRotatorAzimuth(azimuth) }
            }
        )
        rotatorClient = client
        startRotatorFeed(port: settings.rumlogPort)
        client.start()
        record("Rotator: connecting to \(host):\(settings.port)")
    }

    func stopRotator() {
        rotatorFeedReceiver?.stop()
        rotatorFeedReceiver = nil
        rotatorClient?.stop()
        rotatorClient = nil
        rotatorConnectionState = .stopped
        rotatorStatus = "Disconnected"
        rotatorFeedStatus = "RUMlog feed stopped"
        rotatorIsMoving = false
        rotatorMotionDirection = ""
        activeRotatorTarget = nil
    }

    func saveRotatorSettingsAndReconnect() {
        save()
        stopRotator()
        guard configuration.rotator.enabled else { return }
        startRotator()
    }

    func resolveRotatorTarget() {
        let input = rotatorTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            rotatorTargetSource = "Enter a bearing, grid, or call"
            return
        }
        if let bearing = Double(input.replacingOccurrences(of: "°", with: "")), bearing.isFinite, (0...360).contains(bearing) {
            setRotatorTarget(bearing: bearing, label: "Manual", source: "Direct bearing", coordinate: nil)
            return
        }
        if let coordinate = MaidenheadLocator.coordinate(from: input), let home = rotatorHomeCoordinate {
            let bearing = RotatorGeometry.initialBearing(from: home, to: coordinate)
            setRotatorTarget(bearing: bearing, label: input.uppercased(), source: "Maidenhead grid", coordinate: coordinate)
            return
        }
        let call = input.uppercased()
        let path = NSString(string: configuration.rotator.callsignDatabasePath).expandingTildeInPath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8),
              let grid = contents.split(whereSeparator: \.isNewline).reversed().compactMap({ line -> String? in
                  let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                  guard parts.count == 2, parts[0].uppercased() == call else { return nil }
                  return parts[1]
              }).first,
              let coordinate = MaidenheadLocator.coordinate(from: grid),
              let home = rotatorHomeCoordinate else {
            rotatorTargetLabel = call
            rotatorTargetSource = "Call not found in the configured grid database"
            rotatorTargetBearing = nil
            rotatorTargetCoordinate = nil
            rotatorTargetDistanceKilometers = nil
            return
        }
        let bearing = RotatorGeometry.initialBearing(from: home, to: coordinate)
        setRotatorTarget(bearing: bearing, label: call, source: "Call grid \(grid.uppercased())", coordinate: coordinate)
    }

    func turnRotatorToTarget() {
        guard let client = rotatorClient, let bearing = rotatorTargetBearing else {
            rotatorStatus = "Resolve a target and connect first"
            return
        }
        Task { [weak self] in
            do {
                try await client.turn(to: bearing)
                await MainActor.run {
                    guard let self else { return }
                    self.activeRotatorTarget = bearing
                    self.rotatorIsMoving = true
                    self.lastRotatorMovementAt = Date()
                    self.rotatorMotionDirection = self.motionDirection(to: bearing)
                    self.rotatorStatus = self.turningStatus(current: self.rotatorAzimuth, target: bearing)
                    self.scheduleRotatorIdleCheck(after: 2.5)
                    self.record("Rotator: turn to \(Int(bearing.rounded()))°")
                }
            } catch {
                await MainActor.run {
                    self?.rotatorStatus = "Turn failed: \(error.localizedDescription)"
                    self?.record("Rotator: turn failed — \(error.localizedDescription)")
                }
            }
        }
    }

    func turnRotatorFromCompass(to bearing: Double) {
        let normalized = RotatorGeometry.normalized(bearing)
        setRotatorTarget(bearing: normalized, label: "Manual", source: "Compass bearing", coordinate: nil)
        rotatorTargetInput = String(format: "%.0f", normalized)
        turnRotatorToTarget()
    }

    func toggleRotatorPath() {
        guard let bearing = rotatorTargetBearing else { return }
        rotatorTargetBearing = RotatorGeometry.normalized(bearing + 180)
        rotatorTargetSource = rotatorTargetSource.localizedCaseInsensitiveContains("long path")
            ? rotatorTargetSource.replacingOccurrences(of: " · long path", with: "", options: .caseInsensitive)
            : rotatorTargetSource + " · long path"
        if let home = rotatorHomeCoordinate {
            rotatorTargetCoordinate = RotatorGeometry.destination(from: home, bearing: rotatorTargetBearing ?? bearing, distanceKilometers: 5_000)
        }
    }

    func rotateRotator(clockwise: Bool) {
        guard let client = rotatorClient else { return }
        Task { [weak self] in
            do {
                try await client.rotate(clockwise: clockwise)
                await MainActor.run {
                    self?.activeRotatorTarget = nil
                    self?.rotatorIsMoving = true
                    self?.lastRotatorMovementAt = Date()
                    self?.rotatorMotionDirection = clockwise ? "CW" : "CCW"
                    self?.rotatorStatus = clockwise ? "Rotating clockwise" : "Rotating counter-clockwise"
                    self?.scheduleRotatorIdleCheck(after: 2.5)
                    self?.record(clockwise ? "Rotator: clockwise" : "Rotator: counter-clockwise")
                }
            } catch {
                await MainActor.run { self?.rotatorStatus = "Rotate failed: \(error.localizedDescription)" }
            }
        }
    }

    func stopRotatorMotion() {
        guard let client = rotatorClient else { return }
        Task { [weak self] in
            do {
                try await client.stopRotation()
                await MainActor.run {
                    self?.rotatorIsMoving = false
                    self?.rotatorMotionDirection = ""
                    self?.activeRotatorTarget = nil
                    self?.rotatorStatus = "Stop command sent"
                    self?.record("Rotator: stop")
                }
            } catch {
                await MainActor.run { self?.rotatorStatus = "Stop failed: \(error.localizedDescription)" }
            }
        }
    }

    func reloadRemoteConfiguration() {
        guard let remoteAgent else {
            remoteConfigurationStatus = "Remote Station Agent is not running"
            return
        }
        Task { [weak self] in await self?.loadRemoteConfiguration(using: remoteAgent) }
    }

    func saveRemoteConfiguration() {
        guard let remoteAgent else {
            remoteConfigurationStatus = "Remote Station Agent is not running"
            return
        }
        remoteConfigurationBusy = true
        remoteConfigurationStatus = "Saving on Windows"
        let candidate = remoteConfiguration
        Task { [weak self] in
            do {
                let saved = try await remoteAgent.saveConfiguration(candidate)
                await MainActor.run {
                    self?.remoteConfiguration = saved
                    self?.remoteConfigurationLoaded = true
                    self?.remoteConfigurationBusy = false
                    self?.remoteConfigurationStatus = "Saved — restart the Windows agent to apply"
                    self?.record("Station configuration saved on Windows; agent restart required")
                }
            } catch {
                await MainActor.run {
                    self?.remoteConfigurationBusy = false
                    self?.remoteConfigurationStatus = "Save failed: \(error.localizedDescription)"
                    self?.record("Station configuration rejected: \(error.localizedDescription)")
                }
            }
        }
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

    private func applyRemoteAgentSnapshot(_ snapshot: RadioSnapshot) {
        isRadioConnected = snapshot.isConnected
        radioSnapshot = snapshot
        lastSnapshotAt = Date()
        remoteStationStatus = snapshot.remoteStationStatus
        status = Self.radioStatus(snapshot)
        refreshSpotBridgeStatus()

        guard snapshot.frequencyHz != lastTimedFrequency,
              let receivedAt = snapshot.transportReceivedAt else { return }
        let transportMilliseconds = snapshot.agentObservedAt.map {
            max(0, Int(receivedAt.timeIntervalSince($0) * 1_000))
        }
        let timing = TelemetryTiming(
            frequencyHz: snapshot.frequencyHz,
            receivedAt: receivedAt,
            transportMilliseconds: transportMilliseconds
        )
        lastTimedFrequency = snapshot.frequencyHz
        pendingTelemetryTiming = timing
        telemetryLatencySummary = Self.latencySummary(timing)
    }

    private static func latencySummary(_ timing: TelemetryTiming) -> String {
        let transport = timing.transportMilliseconds.map { "Agent→Mac \($0) ms" } ?? "Agent→Mac --"
        let renders = timing.renderMilliseconds.keys.sorted().map {
            "Mac→\($0) \(timing.renderMilliseconds[$0] ?? 0) ms"
        }
        return ([transport] + renders).joined(separator: " · ")
    }

    private func startSpotBridge(radio: any RadioControlling) throws {
        let settings = configuration.spotBridge
        guard settings.logbookPort != settings.contestPort else {
            throw XCatError.server("Logbook and contest spot ports must be different.")
        }
        let logbook = makeSpotReceiver(feed: .logbook, radio: radio)
        let contest = makeSpotReceiver(feed: .contest, radio: radio)
        do {
            try logbook.start(port: settings.logbookPort)
            try contest.start(port: settings.contestPort)
        } catch {
            logbook.stop()
            contest.stop()
            throw error
        }
        logbookSpotReceiver = logbook
        contestSpotReceiver = contest
        refreshSpotBridgeStatus()
        record("Spots: listening on UDP \(settings.logbookPort) / \(settings.contestPort)")
    }

    private func makeSpotReceiver(feed: SpotFeed, radio: any RadioControlling) -> UDPSpotReceiver {
        UDPSpotReceiver(
            label: "com.oliverbross.OM0RXXCat.spots.\(feed.rawValue.lowercased())",
            onDatagram: { [weak self] data in
                Task { @MainActor in self?.handleSpotDatagram(data, feed: feed, radio: radio) }
            },
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.record("Spots \(feed.rawValue): \(event)")
                    if event.contains("failed") { self?.spotBridgeStatus = "Listener error" }
                }
            }
        )
    }

    private func handleSpotDatagram(_ data: Data, feed: SpotFeed, radio: any RadioControlling) {
        spotsReceived += 1
        do {
            let parsed = try RUMlogSpotParser.parse(data, feed: feed)
            let style = configuration.spotBridge.style(for: parsed.category)
            let spot = try parsed.flexSpot(feed: feed, style: style)
            lastSpotSummary = "\(spot.callsign) · \(String(format: "%.3f", Double(spot.frequencyHz) / 1_000_000)) MHz · \(parsed.category.title)"
            if configuration.connectionKind == .remoteAgent,
               remoteStationStatus?.supportedCommands.contains("add_spot") != true {
                spotBridgeStatus = "Listening — Windows agent update required"
                if !spotCapabilityWarningShown {
                    spotCapabilityWarningShown = true
                    record("Spots: Windows agent does not yet advertise add_spot; incoming spots remain local")
                }
                return
            }
            Task { [weak self] in
                do {
                    try await radio.addSpot(spot)
                    await MainActor.run {
                        self?.spotsForwarded += 1
                        self?.spotBridgeStatus = "Listening — forwarding to FLEX"
                        self?.lastSpotError = ""
                        self?.record("Spots: sent \(spot.callsign) to FLEX")
                    }
                } catch {
                    await MainActor.run {
                        self?.spotsRejected += 1
                        let detail = error.localizedDescription
                        if self?.isRadioConnected == false {
                            self?.spotBridgeStatus = "Listening — radio disconnected"
                        } else if detail.localizedCaseInsensitiveContains("authenticate") {
                            self?.spotBridgeStatus = "Listening — agent authentication failed"
                        } else {
                            self?.spotBridgeStatus = "Listening — FLEX rejected last spot"
                        }
                        if self?.lastSpotError != detail {
                            self?.lastSpotError = detail
                            self?.record("Spots: \(spot.callsign) rejected: \(detail)")
                        }
                    }
                }
            }
        } catch {
            spotsRejected += 1
            lastSpotSummary = "Rejected RUMlog datagram"
            record("Spots: rejected UDP datagram: \(error.localizedDescription)")
        }
    }

    private func refreshSpotBridgeStatus() {
        guard configuration.spotBridge.enabled, logbookSpotReceiver != nil, contestSpotReceiver != nil else { return }
        if !isRadioConnected {
            spotBridgeStatus = "Listening — waiting for radio"
        } else if configuration.connectionKind == .remoteAgent,
                  remoteStationStatus?.supportedCommands.contains("add_spot") != true {
            spotBridgeStatus = "Listening — Windows agent update required"
        } else {
            spotCapabilityWarningShown = false
            spotBridgeStatus = "Listening — ready"
        }
    }

    private func startRotatorFeed(port: UInt16) {
        let receiver = UDPSpotReceiver(
            label: "com.oliverbross.OM0RXXCat.rotator.rumlog",
            onDatagram: { [weak self] data in
                Task { @MainActor in self?.handleRotatorDatagram(data) }
            },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.rotatorFeedStatus = event }
            }
        )
        do {
            try receiver.start(port: port)
            rotatorFeedReceiver = receiver
            rotatorFeedStatus = "Listening on UDP \(port)"
        } catch {
            rotatorFeedStatus = "UDP \(port) unavailable — close the old Rotor app"
            record("Rotator: RUMlog feed unavailable — \(error.localizedDescription)")
        }
    }

    private func handleRotatorDatagram(_ data: Data) {
        do {
            let update = try RUMlogRotatorParser.parse(data)
            let home = rotatorHomeCoordinate
            let gridCoordinate = MaidenheadLocator.coordinate(from: update.grid)
            let computed = home.flatMap { origin in gridCoordinate.map { RotatorGeometry.initialBearing(from: origin, to: $0) } }
            let selected: Double?
            let source: String
            if let command = update.commandedBearing {
                selected = command
                source = "RUMlog command"
            } else if configuration.rotator.automaticSource == .station {
                selected = update.stationBearing ?? computed ?? update.countryBearing
                source = update.stationBearing != nil || computed != nil ? "RUMlog station" : "RUMlog DXCC fallback"
            } else {
                selected = update.countryBearing ?? update.stationBearing ?? computed
                source = update.countryBearing != nil ? "RUMlog DXCC" : "RUMlog station fallback"
            }
            guard let selected else { return }
            let band = Self.normalizedBand(update.band.isEmpty ? currentBand : update.band)
            let ruledBearing = applyRotatorBandRules(selected, band: band)
            let label = update.callsign.isEmpty ? configuration.rotator.automaticSource.rawValue : update.callsign
            setRotatorTarget(bearing: ruledBearing, label: label, source: source, coordinate: gridCoordinate, band: band)
            rotatorFeedStatus = "RUMlog: \(label) · \(Int(ruledBearing.rounded()))°"

            if update.commandedBearing != nil {
                turnRotatorToTarget()
            } else if configuration.rotator.automaticTurningEnabled,
                      configuration.rotator.enabledBands.contains(band) {
                commandAutomaticTurnIfNeeded(to: ruledBearing)
            }
        } catch {
            rotatorFeedStatus = "Ignored unsupported RUMlog datagram"
        }
    }

    private func setRotatorTarget(bearing: Double, label: String, source: String, coordinate: GeoCoordinate?, band: String? = nil) {
        let normalized = RotatorGeometry.normalized(bearing)
        rotatorTargetBearing = normalized
        rotatorTargetLabel = label
        rotatorTargetSource = source
        rotatorTargetCoordinate = coordinate
        rotatorTargetBand = band ?? currentBand
        if let home = rotatorHomeCoordinate {
            rotatorTargetDistanceKilometers = coordinate.map { RotatorGeometry.distanceKilometers(from: home, to: $0) }
            if coordinate == nil {
                rotatorTargetCoordinate = RotatorGeometry.destination(from: home, bearing: normalized, distanceKilometers: 5_000)
            }
        } else {
            rotatorTargetDistanceKilometers = nil
        }
    }

    private func applyRotatorBandRules(_ bearing: Double, band: String) -> Double {
        let offset = Double(configuration.rotator.bandOffsets[band] ?? 0)
        let primary = RotatorGeometry.normalized(bearing + offset)
        guard configuration.rotator.bidirectionalBands.contains(band), let current = rotatorAzimuth else { return primary }
        let opposite = RotatorGeometry.normalized(primary + 180)
        return abs(RotatorGeometry.shortestDifference(from: current, to: opposite))
            < abs(RotatorGeometry.shortestDifference(from: current, to: primary)) ? opposite : primary
    }

    private func commandAutomaticTurnIfNeeded(to bearing: Double) {
        guard let current = rotatorAzimuth else { return }
        let difference = abs(RotatorGeometry.shortestDifference(from: current, to: bearing))
        guard difference >= Double(configuration.rotator.minimumAutomaticTurnDegrees) else { return }
        if let previous = lastAutomaticRotatorCommand,
           abs(RotatorGeometry.shortestDifference(from: previous.bearing, to: bearing)) < 0.5,
           Date().timeIntervalSince(previous.date) < 30 { return }
        lastAutomaticRotatorCommand = (bearing, Date())
        turnRotatorToTarget()
    }

    private func applyRotatorAzimuth(_ azimuth: Double) {
        let now = Date()
        let normalized = RotatorGeometry.normalized(azimuth)
        if let previous = lastRotatorAzimuth,
           abs(RotatorGeometry.shortestDifference(from: previous, to: normalized)) >= 0.2 {
            let delta = RotatorGeometry.shortestDifference(from: previous, to: normalized)
            lastRotatorMovementAt = now
            rotatorIsMoving = true
            rotatorMotionDirection = delta >= 0 ? "CW" : "CCW"
        }
        lastRotatorAzimuth = normalized
        rotatorAzimuth = normalized

        if let target = activeRotatorTarget {
            let remaining = abs(RotatorGeometry.shortestDifference(from: normalized, to: target))
            if rotatorIsMoving {
                rotatorStatus = remaining <= 1.0
                    ? "Settling at \(Self.degreesText(target))"
                    : turningStatus(current: normalized, target: target)
            }
        }
        if rotatorIsMoving {
            scheduleRotatorIdleCheck(after: 2.5)
        }
    }

    private func motionDirection(to target: Double) -> String {
        guard let current = rotatorAzimuth else { return "" }
        return RotatorGeometry.shortestDifference(from: current, to: target) >= 0 ? "CW" : "CCW"
    }

    private func turningStatus(current: Double?, target: Double) -> String {
        let direction = motionDirection(to: target)
        guard let current else { return "Turning to \(Self.degreesText(target))" }
        return "Turning \(direction) · \(Self.degreesText(current)) → \(Self.degreesText(target))"
    }

    private func scheduleRotatorIdleCheck(after delay: TimeInterval) {
        let movementStamp = lastRotatorMovementAt
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.lastRotatorMovementAt == movementStamp else { return }
            if let target = self.activeRotatorTarget,
               let current = self.rotatorAzimuth {
                let remaining = abs(RotatorGeometry.shortestDifference(from: current, to: target))
                if remaining <= 2.0 {
                    self.rotatorStatus = "At target \(Self.degreesText(current))"
                    self.activeRotatorTarget = nil
                } else {
                    self.rotatorStatus = "Holding at \(Self.degreesText(current)) · target \(Self.degreesText(target))"
                }
            }
            self.rotatorIsMoving = false
            self.rotatorMotionDirection = ""
        }
    }

    private static func degreesText(_ bearing: Double) -> String {
        String(format: "%03.0f°", RotatorGeometry.normalized(bearing))
    }

    private static func normalizedBand(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if RotatorConfiguration.supportedBands.map({ $0.lowercased() }).contains(value) {
            return RotatorConfiguration.supportedBands.first { $0.lowercased() == value } ?? "Other"
        }
        if value.allSatisfy(\.isNumber) { return "\(value)m" }
        return value.isEmpty ? "Other" : raw
    }

    private func loadRemoteConfiguration(using client: RemoteAgentClient) async {
        remoteConfigurationBusy = true
        remoteConfigurationStatus = "Loading from Windows"
        do {
            let loaded = try await client.fetchConfiguration()
            remoteConfiguration = loaded
            remoteConfigurationLoaded = true
            remoteConfigurationBusy = false
            remoteConfigurationStatus = "Loaded from Windows"
        } catch {
            remoteConfigurationLoaded = false
            remoteConfigurationBusy = false
            remoteConfigurationStatus = "Load failed: \(error.localizedDescription)"
            record("Station configuration unavailable: \(error.localizedDescription)")
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
        ["A", "B"].map { letter in
            guard let vfo = snapshot.vfo(letter) else { return "VFO \(letter) · inactive" }
            let frequency = String(format: "%.3f MHz", Double(vfo.frequencyHz) / 1_000_000)
            let roles = [vfo.isReceive ? "RX" : nil, vfo.isTransmit ? "TX" : nil]
                .compactMap { $0 }
                .joined(separator: "+")
            return "VFO \(letter) · \(roles.isEmpty ? "standby" : roles) · \(frequency) \(vfo.mode)"
        }
        .joined(separator: "\n")
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
