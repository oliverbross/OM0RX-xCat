import Foundation
import Testing
@testable import XCatCore

@Suite("Remote Station Agent", .serialized)
struct RemoteAgentTests {
    @Test func manualReconnectRepeatsOnlyTheReadOnlyStateRequest() async throws {
        RemoteAgentURLProtocol.recorder.reset(stateData: Data(Self.safeState.utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteAgentURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = try RemoteAgentClient(
            baseURL: "https://station.invalid",
            token: "test-credential",
            session: session
        )

        await client.start()
        #expect(await waitForStateRequestCount(1))
        await client.reconnectNow()
        #expect(await waitForStateRequestCount(2))
        await client.stop()
        session.invalidateAndCancel()

        let requests = RemoteAgentURLProtocol.recorder.snapshot()
        #expect(requests.count >= 2)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(requests.allSatisfy { $0.url?.path == "/api/v1/state" })
        #expect(requests.contains { $0.url?.path == "/api/v1/commands" } == false)
    }

    @Test func forwardsAdvertisedTransmitCommandDespiteStationAdvisories() async throws {
        RemoteAgentURLProtocol.recorder.reset(stateData: Data(Self.blockedState.utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteAgentURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = try RemoteAgentClient(
            baseURL: "https://station.invalid",
            token: "test-credential",
            session: session
        )

        await client.start()
        #expect(await waitForStateRequestCount(1))
        try await client.setTransmit(true)
        await client.stop()
        session.invalidateAndCancel()

        let commandRequests = RemoteAgentURLProtocol.recorder.snapshot().filter {
            $0.httpMethod == "POST" && $0.url?.path == "/api/v1/commands"
        }
        #expect(commandRequests.count == 1)
    }

    @Test func decodesAuthoritativeTwoVFOAndStationState() throws {
        let receivedAt = Date(timeIntervalSince1970: 1_760_000_000.75)
        let decoded = try RemoteAgentStateDecoder.stateResponse(Data(Self.safeState.utf8), receivedAt: receivedAt)
        let snapshot = decoded.snapshot

        #expect(snapshot.isConnected)
        #expect(snapshot.frequencyHz == 18_147_000)
        #expect(snapshot.transmitFrequencyHz == 18_153_000)
        #expect(snapshot.vfo("A")?.isReceive == true)
        #expect(snapshot.vfo("A")?.isTransmit == false)
        #expect(snapshot.vfo("B")?.isReceive == false)
        #expect(snapshot.vfo("B")?.isTransmit == true)
        #expect(snapshot.vfo("A")?.ritEnabled == true)
        #expect(snapshot.vfo("A")?.ritOffsetHz == 250)
        #expect(snapshot.vfo("A")?.xitOffsetHz == -100)
        #expect(snapshot.rfPowerWatts == 25)
        #expect(decoded.cwSpeed == 28)
        #expect(snapshot.remoteStationStatus?.inhibitors.isEmpty == true)
        #expect(snapshot.remoteStationStatus?.kpaSummary == "KPA OPERATE")
        #expect(snapshot.remoteStationStatus?.kpaOperate == true)
        #expect(snapshot.remoteStationStatus?.katSummary == "KAT ANT1")
        #expect(snapshot.remoteStationStatus?.routeSummary == "Route 17m Beam")
        #expect(snapshot.remoteStationStatus?.alarmSummary == "ALARM clear")
        #expect(snapshot.remoteStationStatus?.allowedActions.contains("tune") == true)
        #expect(snapshot.remoteStationStatus?.interlockState == "READY")
        #expect(snapshot.remoteStationStatus?.txPowerWatts == 0)
        #expect(snapshot.remoteStationStatus?.swr == 1.25)
        #expect(snapshot.remoteStationStatus?.swrIsLive == true)
        #expect(snapshot.remoteStationStatus?.kpaDetailPrimary.contains("OUT 0W") == true)
        #expect(snapshot.remoteStationStatus?.katDetailPrimary.contains("SWR 1.25") == true)
        #expect(snapshot.remoteStationStatus?.routeDetail == "FLEX ANT1 → KPA500 → KAT500 → Beam")
        #expect(snapshot.agentObservedAt == Date(timeIntervalSince1970: 1_760_000_000.25))
        #expect(snapshot.transportReceivedAt == receivedAt)
    }

    @Test func reportsStaleUncommissionedAlarmStateAsAdvisories() throws {
        let decoded = try RemoteAgentStateDecoder.stateResponse(Data(Self.blockedState.utf8))
        let status = try #require(decoded.snapshot.remoteStationStatus)

        #expect(decoded.snapshot.isConnected == false)
        #expect(status.inhibitors.isEmpty == false)
        #expect(status.inhibitors.contains("Radio state stale"))
        #expect(status.inhibitors.contains("Station not commissioned"))
        #expect(status.inhibitors.contains("KPA500 is disconnected"))
        #expect(status.alarmSummary == "ALARM 1")
    }

    @Test func buildsBearerOnlyIdempotentCommandRequest() throws {
        let endpoint = try RemoteAgentEndpoint("https://station.tailnet.ts.net/")
        let command = RemoteAgentCommand.frequency(18_147_000, vfo: "A")
        let request = try RemoteAgentRequestBuilder.commandRequest(
            endpoint: endpoint,
            token: "test-token",
            requestID: "xcat-test-0001",
            command: command
        )
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let arguments = try #require(object["arguments"] as? [String: Any])

        #expect(request.url?.absoluteString == "https://station.tailnet.ts.net/api/v1/commands")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(object["request_id"] as? String == "xcat-test-0001")
        #expect(object["command"] as? String == "set_frequency_hz")
        #expect(arguments["frequency_hz"] as? Int == 18_147_000)
        #expect(arguments["vfo"] as? String == "A")
    }

    @Test func mapsCompleteVersionOneCommandSurface() {
        #expect(RemoteAgentCommand.mode("USB", vfo: "B").name == "set_mode")
        #expect(RemoteAgentCommand.ptt(true).requiresSafeStation)
        #expect(RemoteAgentCommand.ptt(false).requiresSafeStation == false)
        #expect(RemoteAgentCommand.offset(kind: "set_rit", enabled: true, offsetHz: 250, vfo: "A").name == "set_rit")
        #expect(RemoteAgentCommand.offset(kind: "set_xit", enabled: true, offsetHz: -100, vfo: "B").name == "set_xit")
        #expect(RemoteAgentCommand.receiveVFO("B").name == "set_receive_vfo")
        #expect(RemoteAgentCommand.split(true, txFrequencyHz: 18_153_000).name == "set_split")
        #expect(RemoteAgentCommand.rfPower(25).name == "set_rf_power")
        #expect(RemoteAgentCommand.cwSpeed(30).name == "set_cw_speed")
        #expect(RemoteAgentCommand.sendCW("CQ OM0RX").name == "send_cw")
        #expect(RemoteAgentCommand.clearCW.name == "clear_cw")
        #expect(RemoteAgentCommand.station(.standby).requiresSafeStation == false)
        #expect(RemoteAgentCommand.station(.operate).requiresSafeStation)
        #expect(RemoteAgentCommand.station(.tune).name == "station_tune")
        #expect(RemoteAgentCommand.station(.cancel).requiresSafeStation == false)
    }

    @Test func requiresCredentialFreeHTTPSBaseURL() {
        #expect(throws: (any Error).self) { try RemoteAgentEndpoint("http://station.example") }
        #expect(throws: (any Error).self) { try RemoteAgentEndpoint("https://user:secret@station.example") }
        #expect(throws: (any Error).self) { try RemoteAgentEndpoint("https://station.example/?token=secret") }
    }

    @Test func readsAndWritesAuthenticatedRemoteConfiguration() async throws {
        var configurationValue = RemoteStationConfiguration.placeholder
        configurationValue.flex.host = "192.168.0.199"
        configurationValue.policy.amplifierDriveW["20m"] = 25
        let encoded = try JSONEncoder().encode(configurationValue)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let responseData = try JSONSerialization.data(withJSONObject: [
            "success": true,
            "config": object,
            "restart_required": true,
        ])
        RemoteAgentURLProtocol.recorder.reset(stateData: Data(Self.safeState.utf8))
        RemoteAgentURLProtocol.recorder.setConfigData(responseData)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RemoteAgentURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let client = try RemoteAgentClient(
            baseURL: "https://station.invalid",
            token: "test-credential",
            session: session
        )

        var loaded = try await client.fetchConfiguration()
        #expect(loaded.flex.host == "192.168.0.199")
        loaded.policy.amplifierDriveW["20m"] = 30
        _ = try await client.saveConfiguration(loaded)
        session.invalidateAndCancel()

        let requests = RemoteAgentURLProtocol.recorder.snapshot().filter { $0.url?.path == "/api/v1/config" }
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[1].httpMethod == "PUT")
        let body = try JSONEncoder().encode(RemoteConfigUpdateRequest(config: loaded))
        let bodyObject = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let savedConfig = try #require(bodyObject["config"] as? [String: Any])
        let policy = try #require(savedConfig["policy"] as? [String: Any])
        let drive = try #require(policy["amplifier_drive_w"] as? [String: Int])
        #expect(drive["20m"] == 30)
        #expect(String(data: body, encoding: .utf8)?.contains("test-credential") == false)
    }

    private func waitForStateRequestCount(_ count: Int) async -> Bool {
        for _ in 0..<100 {
            if RemoteAgentURLProtocol.recorder.snapshot().count >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    fileprivate static let safeState = """
    {
      "success": true,
      "state": {
        "protocol_version": 1,
        "revision": 42,
        "agent": {"last_error": null},
        "radio": {
          "connected": true,
          "known": true,
          "stale": false,
          "station_bound": true,
          "station_name": "Maestro",
            "updated_at": 1760000000.25,
          "mox": false,
          "interlock_state": "READY",
          "cw_speed": 28,
          "drive": 25,
          "rit_on": true,
          "rit_freq": 250,
          "xit_on": false,
          "xit_freq": -100,
          "vfos": {
            "A": {"index_letter": "A", "frequency_hz": 18147000, "mode": "USB", "active": true, "transmit": false, "in_use": true},
            "B": {"index_letter": "B", "frequency_hz": 18153000, "mode": "USB", "active": false, "transmit": true, "in_use": true}
          },
          "active_receive": {"index_letter": "A", "frequency_hz": 18147000, "mode": "USB"},
          "transmit": {"index_letter": "B", "frequency_hz": 18153000, "mode": "USB"}
        },
        "elecraft": {
          "kpa500": {"enabled": true, "connected": true, "operate": true, "band": "17m", "output_power_w": 0, "swr": 0, "swr_live": false, "temperature_c": 30, "voltage": 68.7, "current": 0, "fault": "0", "firmware": "01.54", "quality": "good"},
          "kat500": {"enabled": true, "connected": true, "mode": "auto", "band": "17m", "antenna": 1, "bypass": false, "tuning": false, "fault": "0", "forward_adc": 0, "reflected_adc": 0, "swr_sample": 1.25, "swr_live": false, "swr_valid": true, "amp_key_interrupted": false, "firmware": "02.16", "quality": "good"}
        },
        "station": {
          "commissioned": true,
          "coordinator_state": "route_verified",
          "allowed_actions": ["standby", "operate", "tune"],
          "route": {"id": "17m-flex-ant1-kat-ant1", "band": "17m", "flex_tx_ant": "ANT1", "kat_antenna": 1, "antenna_name": "Beam", "amplifier_allowed": true, "active_drive_w": 25},
          "path": {"band": "17m", "alignment": "confirmed", "route_label": "FLEX ANT1 → KPA500 → KAT500 → Beam"},
          "issues": [],
          "alarms": {"active_count": 0, "items": []}
        },
        "capabilities": {"commands": ["set_frequency_hz", "set_mode", "set_ptt", "set_rit", "set_xit", "set_receive_vfo", "set_split", "set_rf_power", "set_cw_speed", "send_cw", "clear_cw", "station_standby", "station_operate", "station_tune", "station_cancel"]}
      }
    }
    """

    private static let blockedState = """
    {
      "success": true,
      "state": {
        "protocol_version": 1,
        "revision": 7,
        "radio": {"connected": true, "known": true, "stale": true, "station_bound": true, "frequency": 14.074, "mode": "DIGU", "mox": false},
        "elecraft": {"kpa500": {"enabled": true, "connected": false}, "kat500": {"enabled": true, "connected": true}},
        "station": {
          "commissioned": false,
          "coordinator_state": "commissioning_locked",
          "allowed_actions": ["standby"],
          "issues": [],
          "alarms": {"active_count": 1, "items": [{"code": "kpa500-disconnected", "severity": "critical", "message": "KPA500 is disconnected", "active": true}]}
        },
        "capabilities": {"commands": ["set_ptt", "station_standby"]}
      }
    }
    """
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var stateData = Data(RemoteAgentTests.safeState.utf8)
    private var configData = Data()

    func append(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    func reset(stateData: Data) {
        lock.withLock {
            requests.removeAll()
            self.stateData = stateData
        }
    }

    func snapshot() -> [URLRequest] {
        lock.withLock { requests }
    }

    func setConfigData(_ data: Data) {
        lock.withLock { configData = data }
    }

    func currentConfigData() -> Data {
        lock.withLock { configData }
    }

    func currentStateData() -> Data {
        lock.withLock { stateData }
    }
}

private final class RemoteAgentURLProtocol: URLProtocol, @unchecked Sendable {
    static let recorder = RequestRecorder()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
            && ["/api/v1/state", "/api/v1/commands", "/api/v1/config"].contains(request.url?.path ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recorder.append(request)
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let data: Data
        if request.url?.path == "/api/v1/commands" {
            data = Data("{\"success\":true}".utf8)
        } else if request.url?.path == "/api/v1/config" {
            data = Self.recorder.currentConfigData()
        } else {
            data = Self.recorder.currentStateData()
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
