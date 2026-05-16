import XCTest
@testable import UniversalVoiceProtocol

final class PairingPayloadTests: XCTestCase {
    func testRoundTrip() throws {
        let payload = PairingPayload(
            serviceName: "Bala's Mac",
            deviceUUID: "0E5F1B6C-2C8C-4AAD-A2D6-7B7C0E7F3A11",
            pskBase64: SessionCrypto.freshPSK().base64EncodedString(),
            port: 7842,
            hostHint: "192.168.1.42"
        )
        let qr = try payload.qrString()
        XCTAssertTrue(qr.hasPrefix("uv://"))
        let decoded = try PairingPayload.parse(qrString: qr)
        XCTAssertEqual(decoded, payload)
    }

    func testParseRejectsBadPrefix() {
        XCTAssertThrowsError(try PairingPayload.parse(qrString: "http://example.com"))
    }
}
