import XCTest
@testable import UniversalVoiceProtocol

final class FrameCodecTests: XCTestCase {
    func testHandshakeRoundTrip() throws {
        let salt = SessionCrypto.freshSalt()
        let frame = HandshakeFrame(salt: salt)
        let bytes = HandshakeCodec.encode(frame)
        XCTAssertEqual(bytes.count, HandshakeCodec.frameSize)
        let decoded = try HandshakeCodec.decode(bytes)
        XCTAssertEqual(decoded, frame)
    }

    func testHandshakeRejectsBadMagic() {
        var bytes = HandshakeCodec.encode(HandshakeFrame(salt: SessionCrypto.freshSalt()))
        bytes[0] = 0x00
        XCTAssertThrowsError(try HandshakeCodec.decode(bytes)) { error in
            guard case HandshakeError.badMagic = error else {
                XCTFail("expected badMagic, got \(error)")
                return
            }
        }
    }

    func testHandshakeRejectsShortFrame() {
        let bytes = Data([0x55, 0x56, 0x4F, 0x49, 0x00, 0x01])
        XCTAssertThrowsError(try HandshakeCodec.decode(bytes)) { error in
            guard case HandshakeError.shortFrame = error else {
                XCTFail("expected shortFrame, got \(error)")
                return
            }
        }
    }

    func testHandshakeRejectsBadVersion() {
        var bytes = HandshakeCodec.encode(HandshakeFrame(salt: SessionCrypto.freshSalt()))
        bytes[4] = 0xFF
        bytes[5] = 0xFF
        XCTAssertThrowsError(try HandshakeCodec.decode(bytes)) { error in
            guard case HandshakeError.unsupportedVersion(let v) = error else {
                XCTFail("expected unsupportedVersion, got \(error)")
                return
            }
            XCTAssertEqual(v, 0xFFFF)
        }
    }
}
