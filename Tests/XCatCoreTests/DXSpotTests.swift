// Copyright © 2026 Oliver Bross OM0RX
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import XCatCore

@Suite("RUMlog FLEX spots")
struct DXSpotTests {
    @Test func parsesLogbookSpotAndChoosesHighestMatchingRule() throws {
        let xml = """
        <spot>
          <StationName>OM0RX</StationName>
          <dxcall>vk8rx</dxcall>
          <frequency>14012.430</frequency>
          <spottercall>om0rx</spottercall>
          <timestamp>2026-10-10T10:20:30Z</timestamp>
          <mode>CW</mode>
          <comment>Long path</comment>
          <dxccNotCfd>true</dxccNotCfd>
          <bandNotCfd>true</bandNotCfd>
        </spot>
        """

        let parsed = try RUMlogSpotParser.parse(Data(xml.utf8), feed: .logbook)

        #expect(parsed.callsign == "vk8rx")
        #expect(parsed.frequencyHz == 14_012_430)
        #expect(parsed.category == .dxccNotConfirmed)
        let spot = try parsed.flexSpot(feed: .logbook, style: SpotStyle(priority: 5, colorHex: "#FF453A", lifetimeSeconds: 1_800))
        #expect(spot.callsign == "VK8RX")
        #expect(spot.priority == 5)
        #expect(spot.source == "RUMlogNG Logbook")
    }

    @Test func parsesContestMultiplierBeforeWorkedBefore() throws {
        let xml = """
        <spot><dxcall>K1ABC</dxcall><frequency>21300.5</frequency><newMulti>1</newMulti><wkdB4>1</wkdB4></spot>
        """
        let parsed = try RUMlogSpotParser.parse(Data(xml.utf8), feed: .contest)
        #expect(parsed.frequencyHz == 21_300_500)
        #expect(parsed.category == .newMultiplier)
    }

    @Test func rejectsMissingFrequency() {
        let xml = "<spot><dxcall>K1ABC</dxcall></spot>"
        #expect(throws: (any Error).self) {
            try RUMlogSpotParser.parse(Data(xml.utf8), feed: .logbook)
        }
    }

    @Test func clampsStyleAndSanitizesSpotFields() throws {
        let style = SpotStyle(priority: 99, colorHex: "#ABCDEF", lifetimeSeconds: 1)
        #expect(style.priority == 5)
        #expect(style.lifetimeSeconds == 30)
        let spot = try FlexSpot(
            frequencyHz: 14_074_000,
            callsign: " k1abc ",
            mode: "DIGU|bad",
            source: "RUMlog NG",
            spotter: "om0rx",
            comment: "one|two",
            timestamp: 1,
            lifetimeSeconds: 600,
            priority: 3,
            colorHex: "not-a-color"
        )
        #expect(spot.callsign == "K1ABC")
        #expect(spot.mode.contains("|") == false)
        #expect(spot.colorHex == "#0A84FF")
    }

    @Test func buildsReceiveOnlyRemoteAgentSpotCommand() throws {
        let spot = try FlexSpot(
            frequencyHz: 14_074_000,
            callsign: "K1ABC",
            mode: "DIGU",
            source: "RUMlogNG Logbook",
            spotter: "OM0RX",
            comment: "DX",
            timestamp: 1_791_628_830,
            lifetimeSeconds: 900,
            priority: 4,
            colorHex: "#30D158"
        )
        let command = RemoteAgentCommand.addSpot(spot)
        #expect(command.name == "add_spot")
        #expect(command.requiresSafeStation == false)
        #expect(command.arguments["frequency_hz"] == .integer(14_074_000))
        #expect(command.arguments["callsign"] == .string("K1ABC"))
    }

    @Test func udpReceiverWaitsForReadinessAndRejectsPortCollision() throws {
        let first = UDPSpotReceiver(label: "test.spots.first", onDatagram: { _ in })
        let second = UDPSpotReceiver(label: "test.spots.second", onDatagram: { _ in })
        try first.start(port: 49_321)
        defer { first.stop() }

        #expect(throws: (any Error).self) {
            try second.start(port: 49_321)
        }
        second.stop()
    }
}
