import Testing
@testable import XCatCore

@Suite("RigCtl command processor")
struct RigCtlCommandProcessorTests {
    @Test func reportsFrequencyAndMode() async {
        let radio = SimulatedRadio(snapshot: RadioSnapshot(frequencyHz: 14_074_000, mode: "DIGU"))
        let processor = RigCtlCommandProcessor(radio: radio)

        #expect(await processor.handle("f") == "14074000\n")
        #expect(await processor.handle("m") == "PKTUSB\n0\n")
    }

    @Test func changesFrequencyAndMode() async {
        let radio = SimulatedRadio()
        let processor = RigCtlCommandProcessor(radio: radio)

        #expect(await processor.handle("F 7100000") == "RPRT 0\n")
        #expect(await processor.handle("M CW -1") == "RPRT 0\n")
        #expect((await radio.snapshot()).frequencyHz == 7_100_000)
        #expect((await radio.snapshot()).mode == "CW")
    }

    @Test func transmitRequiresOptInButUnkeyIsAlwaysAllowed() async {
        let radio = SimulatedRadio()
        let safeProcessor = RigCtlCommandProcessor(radio: radio)
        #expect(await safeProcessor.handle("T 1") == "RPRT -1\n")
        #expect((await radio.snapshot()).isTransmitting == false)

        let enabledProcessor = RigCtlCommandProcessor(radio: radio, allowTransmit: true)
        #expect(await enabledProcessor.handle("T 1") == "RPRT 0\n")
        #expect((await radio.snapshot()).isTransmitting == true)
        #expect(await safeProcessor.handle("T 0") == "RPRT 0\n")
        #expect((await radio.snapshot()).isTransmitting == false)
    }

    @Test func doesNotReturnStaleStateWhenOffline() async {
        let radio = SimulatedRadio(snapshot: RadioSnapshot(isConnected: false))
        let processor = RigCtlCommandProcessor(radio: radio)
        #expect(await processor.handle("f") == "RPRT -1\n")
        #expect(await processor.handle("m") == "RPRT -1\n")
    }
}
