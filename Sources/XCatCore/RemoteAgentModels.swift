import Foundation

struct RemoteAgentEndpoint: Equatable, Sendable {
    let baseURL: URL

    init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw XCatError.server("Enter the HTTPS URL published by Tailscale Serve without credentials or query parameters.")
        }
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw XCatError.server("The Remote Agent URL is invalid.") }
        baseURL = url
    }

    func httpRequest(path: String, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url(path: path, webSocket: false))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        return request
    }

    func webSocketRequest(token: String) -> URLRequest {
        var request = URLRequest(url: url(path: "/api/v1/stream", webSocket: true))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    private func url(path: String, webSocket: Bool) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        if webSocket { components.scheme = "wss" }
        let basePath = components.path == "/" ? "" : components.path
        components.path = basePath + (path.hasPrefix("/") ? path : "/\(path)")
        return components.url!
    }
}

enum RemoteAgentArgument: Equatable, Sendable {
    case boolean(Bool)
    case integer(Int64)
    case string(String)

    var jsonValue: Any {
        switch self {
        case let .boolean(value): value
        case let .integer(value): value
        case let .string(value): value
        }
    }
}

struct RemoteAgentCommand: Equatable, Sendable {
    let name: String
    let arguments: [String: RemoteAgentArgument]
    let requiresSafeStation: Bool

    static func frequency(_ frequencyHz: Int64, vfo: String) -> Self {
        Self(name: "set_frequency_hz", arguments: [
            "frequency_hz": .integer(frequencyHz),
            "vfo": .string(vfo),
        ], requiresSafeStation: true)
    }

    static func mode(_ mode: String, vfo: String) -> Self {
        Self(name: "set_mode", arguments: [
            "mode": .string(mode),
            "vfo": .string(vfo),
        ], requiresSafeStation: true)
    }

    static func ptt(_ enabled: Bool) -> Self {
        Self(name: "set_ptt", arguments: ["enabled": .boolean(enabled)], requiresSafeStation: enabled)
    }

    static func offset(kind: String, enabled: Bool, offsetHz: Int, vfo: String?) -> Self {
        var arguments: [String: RemoteAgentArgument] = [
            "enabled": .boolean(enabled),
            "offset_hz": .integer(Int64(offsetHz)),
        ]
        if let vfo { arguments["vfo"] = .string(vfo) }
        return Self(name: kind, arguments: arguments, requiresSafeStation: kind == "set_xit" || enabled)
    }

    static func receiveVFO(_ vfo: String) -> Self {
        Self(name: "set_receive_vfo", arguments: ["vfo": .string(vfo)], requiresSafeStation: true)
    }

    static func split(_ enabled: Bool, txFrequencyHz: Int64?) -> Self {
        var arguments: [String: RemoteAgentArgument] = ["enabled": .boolean(enabled)]
        if let txFrequencyHz { arguments["tx_frequency_hz"] = .integer(txFrequencyHz) }
        return Self(name: "set_split", arguments: arguments, requiresSafeStation: true)
    }

    static func rfPower(_ watts: Int) -> Self {
        Self(name: "set_rf_power", arguments: ["watts": .integer(Int64(watts))], requiresSafeStation: true)
    }

    static func cwSpeed(_ wordsPerMinute: Int) -> Self {
        Self(name: "set_cw_speed", arguments: ["words_per_minute": .integer(Int64(wordsPerMinute))], requiresSafeStation: false)
    }

    static func sendCW(_ text: String) -> Self {
        Self(name: "send_cw", arguments: ["text": .string(text)], requiresSafeStation: true)
    }

    static let clearCW = Self(name: "clear_cw", arguments: [:], requiresSafeStation: false)

    static func station(_ action: RemoteStationAction) -> Self {
        Self(
            name: "station_\(action.rawValue)",
            arguments: [:],
            requiresSafeStation: action == .operate || action == .tune
        )
    }
}

enum RemoteAgentRequestBuilder {
    static func commandRequest(
        endpoint: RemoteAgentEndpoint,
        token: String,
        requestID: String,
        command: RemoteAgentCommand
    ) throws -> URLRequest {
        var request = endpoint.httpRequest(path: "/api/v1/commands", token: token, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "request_id": requestID,
            "command": command.name,
            "arguments": command.arguments.mapValues(\.jsonValue),
        ], options: [.sortedKeys])
        return request
    }
}

struct RemoteAgentDecodedState: Equatable, Sendable {
    let snapshot: RadioSnapshot
    let cwSpeed: Int
}

enum RemoteAgentStateDecoder {
    static func stateResponse(_ data: Data) throws -> RemoteAgentDecodedState {
        let response = try JSONDecoder().decode(StateResponse.self, from: data)
        guard response.success else { throw XCatError.server("Remote Agent rejected the state request.") }
        return try decode(response.state)
    }

    static func streamMessage(_ data: Data) throws -> RemoteAgentDecodedState? {
        let message = try JSONDecoder().decode(StreamMessage.self, from: data)
        guard message.type == "state", let state = message.state else { return nil }
        return try decode(state)
    }

    static func commandResponse(_ data: Data) throws -> RemoteAgentDecodedState? {
        let response = try JSONDecoder().decode(CommandResponse.self, from: data)
        guard response.success else {
            throw XCatError.server(response.error?.message ?? "Remote Agent rejected the command.")
        }
        return try response.state.map(decode)
    }

    private static func decode(_ state: StateDTO) throws -> RemoteAgentDecodedState {
        guard state.protocolVersion == 1 else {
            throw XCatError.server("Remote Agent protocol version \(state.protocolVersion) is not supported.")
        }
        let radio = state.radio ?? RadioDTO()
        let station = state.station ?? StationDTO()
        let capabilities = Set(state.capabilities?.commands ?? [])
        let activeReceiveLetter = radio.activeReceive?.indexLetter?.uppercased()
            ?? radio.vfos?.first(where: { $0.value.active == true })?.key.uppercased()
            ?? "A"
        let transmitLetter = radio.transmit?.indexLetter?.uppercased()
            ?? radio.vfos?.first(where: { $0.value.transmit == true })?.key.uppercased()
            ?? activeReceiveLetter

        var vfos: [RadioVFO] = (radio.vfos ?? [:]).compactMap { key, value in
            guard value.inUse != false,
                  let frequencyHz = value.resolvedFrequencyHz else { return nil }
            let letter = (value.indexLetter ?? key).uppercased()
            guard letter == "A" || letter == "B" else { return nil }
            return RadioVFO(
                letter: letter,
                frequencyHz: frequencyHz,
                mode: value.mode ?? "?",
                isReceive: letter == activeReceiveLetter,
                isTransmit: letter == transmitLetter,
                ritEnabled: value.ritEnabled ?? (letter == activeReceiveLetter ? radio.ritEnabled : false) ?? false,
                ritOffsetHz: value.ritOffsetHz ?? (letter == activeReceiveLetter ? radio.ritOffsetHz : nil) ?? 0,
                xitEnabled: value.xitEnabled ?? (letter == activeReceiveLetter ? radio.xitEnabled : false) ?? false,
                xitOffsetHz: value.xitOffsetHz ?? (letter == activeReceiveLetter ? radio.xitOffsetHz : nil) ?? 0
            )
        }.sorted { $0.letter < $1.letter }

        if vfos.isEmpty, let frequencyHz = radio.resolvedFrequencyHz {
            vfos = [RadioVFO(
                letter: "A",
                frequencyHz: frequencyHz,
                mode: radio.mode ?? "?",
                isReceive: true,
                isTransmit: true
            )]
        }

        let receiveVFO = vfos.first { $0.letter == activeReceiveLetter }
            ?? vfos.first { $0.letter == "A" }
            ?? vfos.first
        let transmitVFO = vfos.first { $0.letter == transmitLetter } ?? receiveVFO
        let radioConnected = radio.connected == true
        let radioKnown = radio.known == true
        let radioStale = radio.stale != false
        let stationBound = radio.stationBound == true
        let commissioned = station.commissioned == true
        let issues = (station.issues ?? []).map { $0.message ?? $0.code ?? "Station blocker" }
        let activeAlarms = (station.alarms?.items ?? []).filter { $0.active != false }
        let activeAlarmCount = max(activeAlarms.count, station.alarms?.activeCount ?? 0)
        var inhibitors: [String] = []
        if !radioConnected { inhibitors.append("Radio disconnected") }
        if !radioKnown { inhibitors.append("Radio state unknown") }
        if radioStale { inhibitors.append("Radio state stale") }
        if !stationBound { inhibitors.append("SmartSDR station unbound") }
        if !commissioned { inhibitors.append("Station not commissioned") }
        let coordinatorState = (station.coordinatorState ?? "unknown").lowercased()
        if commissioned, !["safe_rx", "route_verified"].contains(coordinatorState) {
            inhibitors.append("Station coordinator state: \(coordinatorState)")
        }
        inhibitors.append(contentsOf: issues)
        inhibitors.append(contentsOf: activeAlarms.map { $0.message ?? $0.code ?? "Active station alarm" })
        if activeAlarmCount > 0, activeAlarms.isEmpty { inhibitors.append("Active station alarm") }
        if let error = state.agent?.lastError, !error.isEmpty { inhibitors.append(error) }
        var seenInhibitors = Set<String>()
        inhibitors = inhibitors.filter { seenInhibitors.insert($0).inserted }

        let kpa = state.elecraft?.kpa500
        let kat = state.elecraft?.kat500
        let route = station.route
        let status = RemoteStationStatus(
            revision: state.revision,
            radioKnown: radioKnown,
            radioStale: radioStale,
            stationBound: stationBound,
            commissioned: commissioned,
            coordinatorState: coordinatorState,
            supportedCommands: capabilities,
            allowedActions: Set(station.allowedActions ?? []),
            inhibitors: inhibitors,
            kpaSummary: kpaSummary(kpa),
            katSummary: katSummary(kat),
            routeSummary: routeSummary(route),
            alarmSummary: activeAlarmCount == 0 ? "ALARM clear" : "ALARM \(activeAlarmCount)",
            alarmMessages: activeAlarms.map { $0.message ?? $0.code ?? "Active station alarm" }
        )
        let fallbackFrequency = radio.resolvedFrequencyHz ?? 0
        let snapshot = RadioSnapshot(
            frequencyHz: receiveVFO?.frequencyHz ?? fallbackFrequency,
            mode: receiveVFO?.mode ?? radio.mode ?? "?",
            isConnected: radioConnected && radioKnown && !radioStale && stationBound,
            isTransmitting: radio.mox == true,
            slice: receiveVFO?.letter ?? activeReceiveLetter,
            transmitSlice: transmitVFO?.letter ?? transmitLetter,
            transmitFrequencyHz: transmitVFO?.frequencyHz ?? fallbackFrequency,
            station: radio.stationName ?? "Remote Agent",
            vfos: vfos,
            remoteStationStatus: status,
            rfPowerWatts: radio.drive.map { Int($0.rounded()) }
        )
        return RemoteAgentDecodedState(snapshot: snapshot, cwSpeed: radio.cwSpeed ?? 25)
    }

    private static func kpaSummary(_ state: KPADTO?) -> String {
        guard let state else { return "KPA unknown" }
        if state.enabled == false { return "KPA off" }
        if state.connected != true { return "KPA disconnected" }
        if let fault = state.fault, !fault.isEmpty, fault != "0", fault != "00" { return "KPA FAULT \(fault)" }
        return state.operate == true ? "KPA OPERATE" : "KPA STBY"
    }

    private static func katSummary(_ state: KATDTO?) -> String {
        guard let state else { return "KAT unknown" }
        if state.enabled == false { return "KAT off" }
        if state.connected != true { return "KAT disconnected" }
        if let fault = state.fault, !fault.isEmpty, fault != "0", fault != "00" { return "KAT FAULT \(fault)" }
        if state.tuning == true { return "KAT tuning" }
        let antenna = state.antenna.map { " ANT\($0)" } ?? ""
        return "KAT\(antenna)\(state.bypass == true ? " BYPASS" : "")"
    }

    private static func routeSummary(_ route: RouteDTO?) -> String {
        guard let route else { return "Route unknown" }
        let routeName = route.band ?? route.id ?? "unknown"
        let antenna = route.antennaName ?? route.flexTXAntenna ?? ""
        return "Route \(routeName)\(antenna.isEmpty ? "" : " \(antenna)")"
    }
}

private struct StateResponse: Decodable {
    let success: Bool
    let state: StateDTO
}

private struct StreamMessage: Decodable {
    let type: String
    let state: StateDTO?
}

private struct CommandResponse: Decodable {
    let success: Bool
    let state: StateDTO?
    let error: ErrorDTO?
}

private struct ErrorDTO: Decodable {
    let code: String?
    let message: String?
}

private struct StateDTO: Decodable {
    let protocolVersion: Int
    let revision: Int
    let agent: AgentDTO?
    let radio: RadioDTO?
    let elecraft: ElecraftDTO?
    let station: StationDTO?
    let capabilities: CapabilitiesDTO?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case revision, agent, radio, elecraft, station, capabilities
    }
}

private struct AgentDTO: Decodable {
    let lastError: String?

    enum CodingKeys: String, CodingKey { case lastError = "last_error" }
}

private struct RadioDTO: Decodable {
    var connected: Bool?
    var known: Bool?
    var stale: Bool?
    var stationBound: Bool?
    var stationName: String?
    var frequency: Double?
    var frequencyHz: Int64?
    var mode: String?
    var mox: Bool?
    var cwSpeed: Int?
    var drive: Double?
    var ritEnabled: Bool?
    var ritOffsetHz: Int?
    var xitEnabled: Bool?
    var xitOffsetHz: Int?
    var vfos: [String: VFODTO]?
    var activeReceive: VFODTO?
    var transmit: VFODTO?

    init() {}

    enum CodingKeys: String, CodingKey {
        case connected, known, stale, frequency, mode, mox, vfos, transmit, drive
        case stationBound = "station_bound"
        case stationName = "station_name"
        case frequencyHz = "frequency_hz"
        case cwSpeed = "cw_speed"
        case activeReceive = "active_receive"
        case ritEnabled = "rit_on"
        case ritOffsetHz = "rit_freq"
        case xitEnabled = "xit_on"
        case xitOffsetHz = "xit_freq"
    }

    var resolvedFrequencyHz: Int64? {
        frequencyHz ?? frequency.map { Int64(($0 * 1_000_000).rounded()) }
    }
}

private struct VFODTO: Decodable {
    let indexLetter: String?
    let frequency: Double?
    let frequencyHz: Int64?
    let mode: String?
    let active: Bool?
    let transmit: Bool?
    let inUse: Bool?
    let ritEnabled: Bool?
    let ritOffsetHz: Int?
    let xitEnabled: Bool?
    let xitOffsetHz: Int?

    enum CodingKeys: String, CodingKey {
        case indexLetter = "index_letter"
        case frequency
        case frequencyHz = "frequency_hz"
        case mode, active, transmit
        case inUse = "in_use"
        case ritEnabled = "rit_on"
        case ritOffsetHz = "rit_freq"
        case xitEnabled = "xit_on"
        case xitOffsetHz = "xit_freq"
    }

    var resolvedFrequencyHz: Int64? {
        frequencyHz ?? frequency.map { Int64(($0 * 1_000_000).rounded()) }
    }
}

private struct StationDTO: Decodable {
    var commissioned: Bool?
    var coordinatorState: String?
    var allowedActions: [String]?
    var route: RouteDTO?
    var issues: [IssueDTO]?
    var alarms: AlarmsDTO?

    init() {}

    enum CodingKeys: String, CodingKey {
        case commissioned, route, issues, alarms
        case coordinatorState = "coordinator_state"
        case allowedActions = "allowed_actions"
    }
}

private struct IssueDTO: Decodable {
    let code: String?
    let message: String?
}

private struct AlarmsDTO: Decodable {
    let activeCount: Int?
    let items: [AlarmDTO]?

    enum CodingKeys: String, CodingKey {
        case activeCount = "active_count"
        case items
    }
}

private struct AlarmDTO: Decodable {
    let code: String?
    let severity: String?
    let message: String?
    let active: Bool?
}

private struct RouteDTO: Decodable {
    let id: String?
    let band: String?
    let flexTXAntenna: String?
    let katAntenna: Int?
    let antennaName: String?
    let amplifierAllowed: Bool?
    let activeDriveW: Int?

    enum CodingKeys: String, CodingKey {
        case id, band
        case flexTXAntenna = "flex_tx_ant"
        case katAntenna = "kat_antenna"
        case antennaName = "antenna_name"
        case amplifierAllowed = "amplifier_allowed"
        case activeDriveW = "active_drive_w"
    }
}

private struct ElecraftDTO: Decodable {
    let kpa500: KPADTO?
    let kat500: KATDTO?
}

private struct KPADTO: Decodable {
    let enabled: Bool?
    let connected: Bool?
    let operate: Bool?
    let fault: String?
}

private struct KATDTO: Decodable {
    let enabled: Bool?
    let connected: Bool?
    let antenna: Int?
    let bypass: Bool?
    let tuning: Bool?
    let fault: String?
}

private struct CapabilitiesDTO: Decodable {
    let commands: [String]?
}
