import Testing
@testable import XCatCore

@Suite("SmartLink broker parser")
struct SmartLinkBrokerParserTests {
    @Test func parsesReachableRadioAndPrefersManualPorts() {
        let line = "radio list serial=1234-5678 radio_name=Remote\u{7F}Flex model=FLEX-8400 status=Available public_ip=203.0.113.4 public_tls_port=21000 public_udp_port=22000 upnp_supported=1 public_upnp_tls_port=31000 public_upnp_udp_port=32000"
        let radios = SmartLinkBrokerParser.radios(from: line)

        #expect(radios.count == 1)
        #expect(radios[0].nickname == "Remote Flex")
        #expect(radios[0].tlsPort == 21_000)
        #expect(radios[0].udpPort == 22_000)
    }

    @Test func fallsBackToUPnPPorts() {
        let line = "radio list serial=1234 model=FLEX-8400 status=Available public_ip=203.0.113.4 public_tls_port=-1 public_udp_port=-1 upnp_supported=1 public_upnp_tls_port=21000 public_upnp_udp_port=22000"
        let radio = SmartLinkBrokerParser.radios(from: line).first

        #expect(radio?.tlsPort == 21_000)
        #expect(radio?.udpPort == 22_000)
    }

    @Test func parsesConnectReady() {
        let ready = SmartLinkBrokerParser.connectReady(from: "radio connect_ready handle=secret-handle serial=1234-5678")
        #expect(ready?.handle == "secret-handle")
        #expect(ready?.serial == "1234-5678")
    }
}
