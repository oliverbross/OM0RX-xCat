import Testing
@testable import XCatCore

@Suite("CAT command processor")
struct CATCommandProcessorTests {
    @Test func readsAndWritesFrequency() async {
        let radio = SimulatedRadio(snapshot: RadioSnapshot(frequencyHz: 14_074_000, mode: "DIGU"))
        let processor = CATCommandProcessor(radio: radio)

        #expect(await processor.handle("FA") == "FA00014074000;")
        #expect(await processor.handle("FA00007100000") == nil)
        #expect((await radio.snapshot()).frequencyHz == 7_100_000)
    }

    @Test func mapsKenwoodModes() async {
        let radio = SimulatedRadio(snapshot: RadioSnapshot(frequencyHz: 14_074_000, mode: "DIGU"))
        let processor = CATCommandProcessor(radio: radio)

        #expect(await processor.handle("MD") == "MD9;")
        #expect(await processor.handle("MD3") == nil)
        #expect((await radio.snapshot()).mode == "CW")
    }

    @Test func rejectsUnknownCommands() async {
        let processor = CATCommandProcessor(radio: SimulatedRadio())
        #expect(await processor.handle("NOPE") == "?;")
    }

    @Test func doesNotReturnStaleFrequencyWhenOffline() async {
        let radio = SimulatedRadio(snapshot: RadioSnapshot(frequencyHz: 14_074_000, isConnected: false))
        let processor = CATCommandProcessor(radio: radio)
        #expect(await processor.handle("FA") == "?;")
        #expect(await processor.handle("MD") == "?;")
    }

    @Test func matchesObservedRUMlogPolling() async {
        let radio = SimulatedRadio(snapshot: RadioSnapshot(frequencyHz: 14_022_300, mode: "CW"))
        let processor = CATCommandProcessor(radio: radio)

        #expect(await processor.handle("KS") == "KS025;")
        #expect(await processor.handle("FB") == "?;")
        #expect(await processor.handle("FA") == "FA00014022300;")
        #expect(await processor.handle("AI2") == nil)
        #expect(await processor.handle("AI") == "AI2;")
    }

    @Test func splitAndCWSpeedRoundTrip() async {
        let radio = SimulatedRadio()
        let processor = CATCommandProcessor(radio: radio)

        #expect(await processor.handle("FT1") == nil)
        #expect(await processor.handle("FB00014250000") == nil)
        #expect(await processor.handle("FB") == "FB00014250000;")
        let splitSnapshot = await radio.snapshot()
        #expect(splitSnapshot.vfo("A")?.isReceive == true)
        #expect(splitSnapshot.vfo("A")?.isTransmit == false)
        #expect(splitSnapshot.vfo("B")?.frequencyHz == 14_250_000)
        #expect(splitSnapshot.vfo("B")?.isReceive == false)
        #expect(splitSnapshot.vfo("B")?.isTransmit == true)
        #expect(await processor.handle("KS030") == nil)
        #expect(await processor.handle("KS") == "KS030;")
        #expect(await processor.handle("FR1") == nil)
        #expect(await processor.handle("FT0") == nil)
        #expect(await processor.handle("FA") == "FA00014074000;")
        #expect(await processor.handle("FB") == "FB00014250000;")
        #expect(await processor.handle("FR") == "FR1;")
        #expect(await processor.handle("FT") == "FT0;")
        #expect(await processor.handle("FR0") == nil)
        #expect(await processor.handle("FA") == "FA00014074000;")
        #expect(await processor.handle("FB") == "FB00014250000;")
    }

    @Test func transmitIsOptInButReceiveAlwaysWorks() async {
        let radio = SimulatedRadio(snapshot: RadioSnapshot(isTransmitting: true))
        let safeProcessor = CATCommandProcessor(radio: radio)
        #expect(await safeProcessor.handle("TX") == "?;")
        #expect(await safeProcessor.handle("RX") == nil)
        #expect((await radio.snapshot()).isTransmitting == false)

        let enabledProcessor = CATCommandProcessor(radio: radio, allowTransmit: true)
        #expect(await enabledProcessor.handle("TX1") == nil)
        #expect((await radio.snapshot()).isTransmitting == true)
    }

    @Test func reportsLiveSplitRolesFromRadio() async {
        let radio = SimulatedRadio(snapshot: RadioSnapshot(
            frequencyHz: 18_147_000,
            mode: "USB",
            slice: "A",
            transmitSlice: "B",
            transmitFrequencyHz: 18_153_000,
            vfos: [
                RadioVFO(letter: "A", frequencyHz: 18_147_000, mode: "USB", isReceive: true),
                RadioVFO(letter: "B", frequencyHz: 18_153_000, mode: "USB", isTransmit: true),
            ]
        ))
        let processor = CATCommandProcessor(radio: radio)

        #expect(await processor.handle("FA") == "FA00018147000;")
        #expect(await processor.handle("FB") == "FB00018153000;")
        #expect(await processor.handle("FR") == "FR0;")
        #expect(await processor.handle("FT") == "FT1;")
        #expect(await processor.handle("IF") == "IF00018147000     +0000000000200000010;")
    }
}
