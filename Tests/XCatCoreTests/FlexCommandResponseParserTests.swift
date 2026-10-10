import Testing
@testable import XCatCore

@Suite("Flex command response parser")
struct FlexCommandResponseParserTests {
    @Test func parsesSuccessfulResponse() {
        #expect(FlexCommandResponseParser.parse("R17|0|") == .init(sequence: 17, code: 0, message: ""))
    }

    @Test func parsesRadioErrorWithoutTreatingDebugAsMessage() {
        #expect(
            FlexCommandResponseParser.parse("R9|500000AA|Invalid command|debug")
                == .init(sequence: 9, code: 0x500000AA, message: "Invalid command")
        )
    }

    @Test func rejectsMalformedFrames() {
        #expect(FlexCommandResponseParser.parse("S1|slice 0") == nil)
        #expect(FlexCommandResponseParser.parse("Rnope|0|") == nil)
    }
}
