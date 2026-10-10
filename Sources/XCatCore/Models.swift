import Foundation

public enum RadioConnectionState: String, Codable, Sendable {
    case stopped
    case discovering
    case authenticating
    case connecting
    case ready
    case retrying
    case failed
}

public struct RadioSnapshot: Equatable, Sendable {
    public var frequencyHz: Int64
    public var mode: String
    public var isTransmitting: Bool
    public var slice: String
    public var station: String

    public init(
        frequencyHz: Int64 = 14_074_000,
        mode: String = "DIGU",
        isTransmitting: Bool = false,
        slice: String = "A",
        station: String = ""
    ) {
        self.frequencyHz = frequencyHz
        self.mode = mode
        self.isTransmitting = isTransmitting
        self.slice = slice
        self.station = station
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public enum ConnectionKind: String, Codable, CaseIterable, Sendable {
        case smartLink = "SmartLink"
        case local = "Local network"
        case simulator = "Simulator"
    }

    public var connectionKind: ConnectionKind
    public var radioHost: String
    public var radioPort: UInt16
    public var stationName: String
    public var sliceLetter: String
    public var catPort: UInt16
    public var rigCtlPort: UInt16
    public var allowCATTransmit: Bool
    public var launchServersAutomatically: Bool

    public init(
        connectionKind: ConnectionKind = .smartLink,
        radioHost: String = "",
        radioPort: UInt16 = 4992,
        stationName: String = "Maestro",
        sliceLetter: String = "A",
        catPort: UInt16 = 5002,
        rigCtlPort: UInt16 = 4532,
        allowCATTransmit: Bool = false,
        launchServersAutomatically: Bool = true
    ) {
        self.connectionKind = connectionKind
        self.radioHost = radioHost
        self.radioPort = radioPort
        self.stationName = stationName
        self.sliceLetter = sliceLetter
        self.catPort = catPort
        self.rigCtlPort = rigCtlPort
        self.allowCATTransmit = allowCATTransmit
        self.launchServersAutomatically = launchServersAutomatically
    }

    private enum CodingKeys: String, CodingKey {
        case connectionKind, radioHost, radioPort, stationName, sliceLetter
        case catPort, rigCtlPort, allowCATTransmit, launchServersAutomatically
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        connectionKind = try values.decodeIfPresent(ConnectionKind.self, forKey: .connectionKind) ?? .smartLink
        radioHost = try values.decodeIfPresent(String.self, forKey: .radioHost) ?? ""
        radioPort = try values.decodeIfPresent(UInt16.self, forKey: .radioPort) ?? 4992
        stationName = try values.decodeIfPresent(String.self, forKey: .stationName) ?? "Maestro"
        sliceLetter = try values.decodeIfPresent(String.self, forKey: .sliceLetter) ?? "A"
        catPort = try values.decodeIfPresent(UInt16.self, forKey: .catPort) ?? 5002
        rigCtlPort = try values.decodeIfPresent(UInt16.self, forKey: .rigCtlPort) ?? 4532
        allowCATTransmit = try values.decodeIfPresent(Bool.self, forKey: .allowCATTransmit) ?? false
        launchServersAutomatically = try values.decodeIfPresent(Bool.self, forKey: .launchServersAutomatically) ?? true
    }
}

public enum CATTransmitMode: Sendable {
    case microphone
    case data
    case tune
}

public protocol RadioControlling: Actor {
    func snapshot() async -> RadioSnapshot
    func setFrequency(_ frequencyHz: Int64) async throws
    func setMode(_ mode: String) async throws
    func setTransmit(_ enabled: Bool) async throws
    func secondaryFrequency() async -> Int64?
    func setSecondaryFrequency(_ frequencyHz: Int64) async throws
    func setSplitTransmit(_ enabled: Bool) async throws
    func setReceiveVFO(_ vfo: Int) async throws
    func cwSpeed() async -> Int
    func setCWSpeed(_ wordsPerMinute: Int) async throws
    func sendCW(_ text: String) async throws
    func clearCW() async throws
    func setTransmit(_ mode: CATTransmitMode) async throws
}

public extension RadioControlling {
    func secondaryFrequency() async -> Int64? { nil }
    func setSecondaryFrequency(_ frequencyHz: Int64) async throws { throw XCatError.unsupported }
    func setSplitTransmit(_ enabled: Bool) async throws {
        if enabled { throw XCatError.unsupported }
    }
    func setReceiveVFO(_ vfo: Int) async throws {
        if vfo != 0 { throw XCatError.unsupported }
    }
    func cwSpeed() async -> Int { 25 }
    func setCWSpeed(_ wordsPerMinute: Int) async throws { throw XCatError.unsupported }
    func sendCW(_ text: String) async throws { throw XCatError.unsupported }
    func clearCW() async throws { throw XCatError.unsupported }
    func setTransmit(_ mode: CATTransmitMode) async throws { try await setTransmit(true) }
}

public enum XCatError: LocalizedError, Sendable {
    case invalidFrequency
    case invalidMode
    case notConnected
    case unsupported
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFrequency: "The frequency is invalid."
        case .invalidMode: "The radio mode is invalid."
        case .notConnected: "The radio is not connected."
        case .unsupported: "This operation is not supported by the selected radio connection."
        case let .server(message): message
        }
    }
}
