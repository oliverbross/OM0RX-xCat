import Foundation
import Testing
@testable import XCatCore

@Suite("SmartLink authentication")
struct SmartLinkAuthTests {
    @Test func buildsEstablishedPasswordRealmGrant() {
        let body = SmartLinkAuthenticator.passwordGrantBody(
            email: "operator@example.com",
            password: "test-only-secret"
        )

        #expect(body["grant_type"] == "http://auth0.com/oauth/grant-type/password-realm")
        #expect(body["realm"] == "Username-Password-Authentication")
        #expect(body["username"] == "operator@example.com")
        #expect(body["password"] == "test-only-secret")
        #expect(body["client_id"] == SmartLinkAuthenticator.clientID)
        #expect(body["scope"]?.contains("offline_access") == true)
    }

    @Test func oldSettingsDecodeWithSafeSmartLinkDefaults() throws {
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: Data("{}".utf8))

        #expect(configuration.smartLinkEmail.isEmpty)
        #expect(configuration.smartLinkRadioSerial.isEmpty)
        #expect(configuration.allowCATTransmit == false)
    }
}
