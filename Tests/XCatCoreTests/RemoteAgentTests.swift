import Foundation
import Testing
@testable import XCatCore

@Suite("Remote Station Agent")
struct RemoteAgentTests {
    @Test func decodesAuthoritativeTwoVFOAndStationState() throws {
        let decoded = try RemoteAgentStateDecoder.stateResponse(Data(Self.safeState.utf8))
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
        #expect(snapshot.remoteStationStatus?.hazardousWritesAllowed == true)
        #expect(snapshot.remoteStationStatus?.kpaSummary == "KPA OPERATE")
        #expect(snapshot.remoteStationStatus?.katSummary == "KAT ANT1")
        #expect(snapshot.remoteStationStatus?.routeSummary == "Route 17m Beam")
        #expect(snapshot.remoteStationStatus?.alarmSummary == "ALARM clear")
        #expect(snapshot.remoteStationStatus?.allows(.tune) == true)
    }

    @Test func staleUncommissionedAlarmStateFailsClosed() throws {
        let decoded = try RemoteAgentStateDecoder.stateResponse(Data(Self.blockedState.utf8))
        let status = try #require(decoded.snapshot.remoteStationStatus)

        #expect(decoded.snapshot.isConnected == false)
        #expect(status.hazardousWritesAllowed == false)
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

    private static let safeState = """
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
          "mox": false,
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
          "kpa500": {"enabled": true, "connected": true, "operate": true, "fault": "0"},
          "kat500": {"enabled": true, "connected": true, "antenna": 1, "bypass": false, "tuning": false, "fault": "0"}
        },
        "station": {
          "commissioned": true,
          "coordinator_state": "route_verified",
          "allowed_actions": ["standby", "operate", "tune"],
          "route": {"id": "17m-flex-ant1-kat-ant1", "band": "17m", "flex_tx_ant": "ANT1", "kat_antenna": 1, "antenna_name": "Beam", "amplifier_allowed": true, "active_drive_w": 25},
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
