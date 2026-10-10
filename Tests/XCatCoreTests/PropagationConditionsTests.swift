// Copyright © 2026 Oliver Bross OM0RX
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import XCatCore

@Suite("HF propagation conditions")
struct PropagationConditionsTests {
    @Test func parsesN0NBHSolarXML() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8" ?>
        <solar><solardata>
          <updated> 10 Oct 2026 1629 GMT</updated>
          <solarflux>121</solarflux><aindex>11</aindex><kindex>3</kindex><xray>M1.0</xray>
          <calculatedconditions>
            <band name="80m-40m" time="day">Poor</band><band name="80m-40m" time="night">Fair</band>
            <band name="30m-20m" time="day">Good</band><band name="30m-20m" time="night">Good</band>
            <band name="17m-15m" time="day">Fair</band><band name="17m-15m" time="night">Fair</band>
            <band name="12m-10m" time="day">Fair</band><band name="12m-10m" time="night">Poor</band>
          </calculatedconditions>
          <calculatedvhfconditions>
            <phenomenon name="E-Skip" location="europe_6m">Band Closed</phenomenon>
          </calculatedvhfconditions>
        </solardata></solar>
        """.utf8)

        let snapshot = try PropagationConditionsParser.parse(xml)

        #expect(snapshot.solarFlux == 121)
        #expect(snapshot.aIndex == 11)
        #expect(snapshot.kIndex == 3)
        #expect(snapshot.xRay == "M1.0")
        #expect(snapshot.bands.count == 4)
        #expect(snapshot.bands[0].day == .poor)
        #expect(snapshot.bands[0].night == .fair)
        #expect(snapshot.bands[1].day == .good)
        #expect(snapshot.sixMeterEurope == .closed)
        #expect(snapshot.updatedAt != nil)
    }

    @Test func rejectsFeedWithoutBandConditions() {
        let xml = Data("<solar><solardata><solarflux>121</solarflux></solardata></solar>".utf8)
        #expect(throws: (any Error).self) {
            try PropagationConditionsParser.parse(xml)
        }
    }
}
