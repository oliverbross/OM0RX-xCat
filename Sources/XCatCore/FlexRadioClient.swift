@preconcurrency import Network
import Foundation

public actor FlexRadioClient: RadioControlling {
    public typealias StateHandler = @Sendable (RadioConnectionState, String) -> Void
    public typealias SnapshotHandler = @Sendable (RadioSnapshot) -> Void

    private struct SliceState: Sendable {
        var id: Int
        var frequencyMHz: Double?
        var mode: String?
        var clientHandle: String?
        var indexLetter: String?
        var active = false
        var transmit = false
    }

    private let host: String
    private let port: UInt16
    private let stationName: String
    private let sliceLetter: String
    private let onState: StateHandler
    private let onSnapshot: SnapshotHandler
    private let queue = DispatchQueue(label: "com.oliverbross.OM0RXXCat.radio")

    private var connection: NWConnection?
    private var generation = 0
    private var shouldRun = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var inboundBuffer = Data()
    private var commandSequence = 1
    private var state: RadioConnectionState = .stopped
    private var value: RadioSnapshot
    private var slices: [Int: SliceState] = [:]
    private var selectedSliceID: Int?
    private var followedClientHandle: String?
    private var followedClientID: String?

    public init(
        host: String,
        port: UInt16 = 4992,
        stationName: String,
        sliceLetter: String = "A",
        onState: @escaping StateHandler = { _, _ in },
        onSnapshot: @escaping SnapshotHandler = { _ in }
    ) {
        self.host = host
        self.port = port
        self.stationName = stationName
        self.sliceLetter = sliceLetter.uppercased()
        self.onState = onState
        self.onSnapshot = onSnapshot
        value = RadioSnapshot(slice: sliceLetter.uppercased(), station: stationName)
    }

    public func start() {
        guard !shouldRun else { return }
        shouldRun = true
        reconnectAttempt = 0
        connect()
    }

    public func stop() {
        shouldRun = false
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        generation += 1
        connection?.cancel()
        connection = nil
        inboundBuffer.removeAll(keepingCapacity: false)
        transition(.stopped, "Stopped")
    }

    public func reconnectNow() {
        guard shouldRun else {
            start()
            return
        }
        reconnectAttempt = 0
        generation += 1
        connection?.cancel()
        connection = nil
        connect()
    }

    public func snapshot() -> RadioSnapshot {
        value
    }

    public func setFrequency(_ frequencyHz: Int64) async throws {
        guard frequencyHz > 0 else { throw XCatError.invalidFrequency }
        guard let selectedSliceID else { throw XCatError.notConnected }
        try await sendCommand("slice t \(selectedSliceID) \(Self.formatMHz(frequencyHz))")
    }

    public func setMode(_ mode: String) async throws {
        let normalized = mode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty, normalized.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw XCatError.invalidMode
        }
        guard let selectedSliceID else { throw XCatError.notConnected }
        try await sendCommand("slice s \(selectedSliceID) mode=\(normalized)")
    }

    public func setTransmit(_ enabled: Bool) async throws {
        guard state == .ready else { throw XCatError.notConnected }
        try await sendCommand("xmit \(enabled ? 1 : 0)")
    }

    public func cwSpeed() -> Int { 25 }

    public func setCWSpeed(_ wordsPerMinute: Int) async throws {
        guard (5...100).contains(wordsPerMinute) else { throw XCatError.server("CW speed must be 5 through 100 WPM.") }
        try await sendCommand("cw wpm=\(wordsPerMinute)")
    }

    public func sendCW(_ text: String) async throws {
        guard !text.isEmpty, text.count <= 128 else { throw XCatError.server("CW text must contain 1 through 128 characters.") }
        let safeText = text.replacingOccurrences(of: "|", with: " ")
        try await sendCommand("cwx send \(safeText)")
    }

    public func clearCW() async throws {
        try await sendCommand("cwx clear")
        try? await setTransmit(false)
    }

    public func setTransmit(_ mode: CATTransmitMode) async throws {
        switch mode {
        case .microphone, .data:
            try await setTransmit(true)
        case .tune:
            try await sendCommand("transmit tune 1")
        }
    }

    private func connect() {
        guard shouldRun, connection == nil else { return }
        generation += 1
        let currentGeneration = generation
        resetSessionState()
        transition(.connecting, "Connecting to \(host):\(port)")

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            transition(.failed, "Invalid radio port")
            return
        }
        let newConnection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        connection = newConnection
        newConnection.stateUpdateHandler = { [weak self] networkState in
            Task { await self?.handle(networkState, generation: currentGeneration) }
        }
        newConnection.start(queue: queue)
    }

    private func handle(_ networkState: NWConnection.State, generation currentGeneration: Int) async {
        guard currentGeneration == generation else { return }
        switch networkState {
        case .ready:
            reconnectAttempt = 0
            transition(.ready, "Connected; waiting for \(stationName) slice \(sliceLetter)")
            receive(generation: currentGeneration)
            do {
                try await bootstrap()
                startPingLoop(generation: currentGeneration)
            } catch {
                await connectionFailed("Bootstrap failed: \(error.localizedDescription)", generation: currentGeneration)
            }
        case let .waiting(error):
            await connectionFailed("Network waiting: \(error.localizedDescription)", generation: currentGeneration)
        case let .failed(error):
            await connectionFailed("Connection failed: \(error.localizedDescription)", generation: currentGeneration)
        case .cancelled:
            if shouldRun, currentGeneration == generation {
                await connectionFailed("Connection closed", generation: currentGeneration)
            }
        default:
            break
        }
    }

    private func bootstrap() async throws {
        try await sendCommand("client program OM0RX-xCat")
        try await sendCommand("sub client all")
        try await sendCommand("sub slice all")
        try await sendCommand("sub interlock all")
        try await sendCommand("sub radio all")
        try await sendCommand("keepalive enable")
        try await sendCommand("slice list")
        try await sendCommand("ping")
    }

    private func startPingLoop(generation currentGeneration: Int) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                do {
                    try await self?.sendCommand("ping")
                } catch {
                    await self?.connectionFailed("Radio heartbeat failed", generation: currentGeneration)
                    return
                }
            }
        }
    }

    private func receive(generation currentGeneration: Int) {
        guard currentGeneration == generation, let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task {
                guard let self else { return }
                if let data, !data.isEmpty {
                    await self.consume(data, generation: currentGeneration)
                }
                if complete || error != nil {
                    await self.connectionFailed(
                        error.map { "Receive failed: \($0.localizedDescription)" } ?? "Radio closed the connection",
                        generation: currentGeneration
                    )
                } else {
                    await self.receive(generation: currentGeneration)
                }
            }
        }
    }

    private func consume(_ data: Data, generation currentGeneration: Int) {
        guard currentGeneration == generation else { return }
        inboundBuffer.append(data)
        if inboundBuffer.count > 1_048_576 {
            inboundBuffer.removeAll(keepingCapacity: true)
            return
        }
        while let newline = inboundBuffer.firstIndex(of: 0x0A) {
            let lineData = inboundBuffer[..<newline]
            inboundBuffer.removeSubrange(...newline)
            guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { continue }
            parse(line)
        }
    }

    private func parse(_ line: String) {
        guard line.first == "S" else { return }
        let payload = line.dropFirst()
        let statusParts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard statusParts.count == 2 else { return }
        let body = String(statusParts[1])
        let tokens = body.split(separator: " ")
        guard let object = tokens.first else { return }

        var identifier: String?
        var propertyStart = 1
        if tokens.count > 1, !tokens[1].contains("=") {
            identifier = String(tokens[1])
            propertyStart = 2
        }
        var properties: [String: String] = [:]
        for token in tokens.dropFirst(propertyStart) {
            let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { properties[pair[0]] = pair[1] }
        }

        switch object {
        case "client", "gui_client":
            applyClient(identifier: identifier, properties: properties)
        case "slice":
            applySlice(identifier: identifier, properties: properties)
        case "interlock":
            if let interlock = properties["state"]?.uppercased() {
                value.isTransmitting = interlock == "TRANSMITTING" || interlock == "PTT_REQUESTED"
                publishSnapshot()
            }
        default:
            break
        }
    }

    private func applyClient(identifier: String?, properties: [String: String]) {
        guard Self.normalizedStation(properties["station"]) == Self.normalizedStation(stationName) else { return }
        followedClientHandle = Self.normalizedHandle(identifier ?? properties["handle"])
        followedClientID = properties["client_id"]
        if let followedClientID {
            Task { try? await sendCommand("client bind client_id=\(followedClientID)") }
        }
        selectBestSlice()
    }

    private func applySlice(identifier: String?, properties: [String: String]) {
        guard let identifier, let id = Int(identifier) else { return }
        if properties["removed"] == "1" || properties.keys.contains("removed") {
            slices.removeValue(forKey: id)
            if selectedSliceID == id { selectedSliceID = nil }
            selectBestSlice()
            return
        }
        var slice = slices[id] ?? SliceState(id: id)
        if let frequency = properties["RF_frequency"].flatMap(Double.init) ?? properties["freq"].flatMap(Double.init) {
            slice.frequencyMHz = frequency
        }
        if let mode = properties["mode"] { slice.mode = mode.uppercased() }
        if let handle = properties["client_handle"] { slice.clientHandle = Self.normalizedHandle(handle) }
        if let letter = properties["index_letter"] { slice.indexLetter = letter.uppercased() }
        if let active = properties["active"] { slice.active = active == "1" || active.uppercased() == "T" }
        if let transmit = properties["tx"] { slice.transmit = transmit == "1" || transmit.uppercased() == "T" }
        slices[id] = slice
        selectBestSlice()
    }

    private func selectBestSlice() {
        let candidates = slices.values.filter { slice in
            let letterMatches = slice.indexLetter == nil || slice.indexLetter == sliceLetter
            let clientMatches = followedClientHandle == nil || slice.clientHandle == followedClientHandle
            return letterMatches && clientMatches
        }
        let selected = candidates.sorted { lhs, rhs in
            if lhs.indexLetter == sliceLetter, rhs.indexLetter != sliceLetter { return true }
            if lhs.indexLetter != sliceLetter, rhs.indexLetter == sliceLetter { return false }
            if lhs.active != rhs.active { return lhs.active }
            if lhs.transmit != rhs.transmit { return lhs.transmit }
            return lhs.id < rhs.id
        }.first
        guard let selected else { return }
        selectedSliceID = selected.id
        if let frequencyMHz = selected.frequencyMHz {
            value.frequencyHz = Int64((frequencyMHz * 1_000_000).rounded())
        }
        if let mode = selected.mode { value.mode = mode }
        value.slice = selected.indexLetter ?? sliceLetter
        value.station = stationName
        publishSnapshot()
        transition(.ready, "Following \(stationName), slice \(value.slice)")
    }

    private func publishSnapshot() {
        onSnapshot(value)
    }

    private func sendCommand(_ body: String) async throws {
        guard state == .ready, let connection else { throw XCatError.notConnected }
        let sequence = commandSequence
        commandSequence += 1
        let command = "C\(sequence)|\(body)\n"
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: Data(command.utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func connectionFailed(_ message: String, generation currentGeneration: Int) async {
        guard currentGeneration == generation else { return }
        pingTask?.cancel()
        pingTask = nil
        generation += 1
        connection?.cancel()
        connection = nil
        guard shouldRun else {
            transition(.stopped, "Stopped")
            return
        }
        scheduleReconnect(message)
    }

    private func scheduleReconnect(_ message: String) {
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let base = min(pow(2.0, Double(max(0, reconnectAttempt - 1))), 30.0)
        let jitter = Double.random(in: 0...(base * 0.25))
        let delay = base + jitter
        transition(.retrying, "\(message). Retrying in \(String(format: "%.1f", delay)) s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }

    private func resetSessionState() {
        pingTask?.cancel()
        pingTask = nil
        inboundBuffer.removeAll(keepingCapacity: true)
        commandSequence = 1
        slices.removeAll(keepingCapacity: true)
        selectedSliceID = nil
        followedClientHandle = nil
        followedClientID = nil
    }

    private func transition(_ newState: RadioConnectionState, _ description: String) {
        state = newState
        onState(newState, description)
    }

    private static func normalizedHandle(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("0x") { value.removeFirst(2) }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
    }

    private static func normalizedStation(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\u{7F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func formatMHz(_ hertz: Int64) -> String {
        String(format: "%.6f", Double(hertz) / 1_000_000)
    }
}
