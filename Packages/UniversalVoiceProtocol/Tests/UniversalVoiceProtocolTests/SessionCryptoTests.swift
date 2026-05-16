import XCTest
import CryptoKit
@testable import UniversalVoiceProtocol

final class SessionCryptoTests: XCTestCase {
    private func freshKey() -> SymmetricKey {
        SessionCrypto.deriveSessionKey(
            psk: SessionCrypto.freshPSK(),
            saltInitiator: SessionCrypto.freshSalt(),
            saltResponder: SessionCrypto.freshSalt()
        )
    }

    func testRoundTripText() throws {
        let key = freshKey()
        var initiator = SessionCrypto(key: key, role: .initiator)
        var responder = SessionCrypto(key: key, role: .responder)
        let payload = TextPayload(
            segmentId: UUID(),
            content: "Hello, world.",
            isFinalUtterance: true
        )
        let frame = try initiator.seal(.text(payload))
        XCTAssertEqual(try responder.open(frame), .text(payload))
    }

    func testRoundTripPing() throws {
        let key = freshKey()
        var initiator = SessionCrypto(key: key, role: .initiator)
        var responder = SessionCrypto(key: key, role: .responder)
        let frame = try initiator.seal(.ping)
        XCTAssertEqual(try responder.open(frame), .ping)
    }

    func testRoundTripContext() throws {
        let key = freshKey()
        var initiator = SessionCrypto(key: key, role: .initiator)
        var responder = SessionCrypto(key: key, role: .responder)
        let resp = ContextPayload(
            focusedBundleId: "com.apple.dt.Xcode",
            focusedAppName: "Xcode"
        )
        let req = try initiator.seal(.contextRequest)
        XCTAssertEqual(try responder.open(req), .contextRequest)

        let reply = try responder.seal(.contextResponse(resp))
        XCTAssertEqual(try initiator.open(reply), .contextResponse(resp))
    }

    func testReplayRejected() throws {
        let key = freshKey()
        var initiator = SessionCrypto(key: key, role: .initiator)
        var responder = SessionCrypto(key: key, role: .responder)
        let frame = try initiator.seal(.ping)
        _ = try responder.open(frame)
        XCTAssertThrowsError(try responder.open(frame)) { error in
            guard case SessionError.replayedNonce = error else {
                XCTFail("expected replayedNonce, got \(error)")
                return
            }
        }
    }

    func testOutOfOrderRejected() throws {
        let key = freshKey()
        var initiator = SessionCrypto(key: key, role: .initiator)
        var responder = SessionCrypto(key: key, role: .responder)
        let f1 = try initiator.seal(.ping)
        let f2 = try initiator.seal(.ping)
        _ = try responder.open(f2)
        XCTAssertThrowsError(try responder.open(f1)) { error in
            guard case SessionError.replayedNonce = error else {
                XCTFail("expected replayedNonce, got \(error)")
                return
            }
        }
    }

    func testWrongPSKRejected() throws {
        let saltI = SessionCrypto.freshSalt()
        let saltR = SessionCrypto.freshSalt()
        let keyA = SessionCrypto.deriveSessionKey(
            psk: SessionCrypto.freshPSK(),
            saltInitiator: saltI,
            saltResponder: saltR
        )
        let keyB = SessionCrypto.deriveSessionKey(
            psk: SessionCrypto.freshPSK(),
            saltInitiator: saltI,
            saltResponder: saltR
        )
        var sealer = SessionCrypto(key: keyA, role: .initiator)
        var opener = SessionCrypto(key: keyB, role: .responder)
        let frame = try sealer.seal(.ping)
        XCTAssertThrowsError(try opener.open(frame)) { error in
            guard case SessionError.decryptionFailed = error else {
                XCTFail("expected decryptionFailed, got \(error)")
                return
            }
        }
    }

    func testCrossDirectionRejected() throws {
        let key = freshKey()
        // Two initiators built from the same key. A frame sealed by one targets
        // the responder direction byte and must be rejected by the other.
        var sealerA = SessionCrypto(key: key, role: .initiator)
        var sealerB = SessionCrypto(key: key, role: .initiator)
        let frame = try sealerA.seal(.ping)
        XCTAssertThrowsError(try sealerB.open(frame)) { error in
            guard case SessionError.wrongDirection = error else {
                XCTFail("expected wrongDirection, got \(error)")
                return
            }
        }
    }

    func testManySequentialFrames() throws {
        let key = freshKey()
        var initiator = SessionCrypto(key: key, role: .initiator)
        var responder = SessionCrypto(key: key, role: .responder)
        for i in 0..<256 {
            let payload = TextPayload(
                segmentId: UUID(),
                content: "msg \(i)",
                isFinalUtterance: i == 255
            )
            let frame = try initiator.seal(.text(payload))
            XCTAssertEqual(try responder.open(frame), .text(payload))
        }
    }

    func testBothDirections() throws {
        let key = freshKey()
        var initiator = SessionCrypto(key: key, role: .initiator)
        var responder = SessionCrypto(key: key, role: .responder)
        let f1 = try initiator.seal(.text(TextPayload(
            segmentId: UUID(), content: "a", isFinalUtterance: false
        )))
        _ = try responder.open(f1)
        let ctx = ContextPayload(focusedBundleId: "x", focusedAppName: "X")
        let f2 = try responder.seal(.contextResponse(ctx))
        XCTAssertEqual(try initiator.open(f2), .contextResponse(ctx))
    }

    func testDerivedKeyDeterministic() {
        let psk = Data(repeating: 0xAB, count: 32)
        let saltI = Data(repeating: 0x01, count: 16)
        let saltR = Data(repeating: 0x02, count: 16)
        let key1 = SessionCrypto.deriveSessionKey(
            psk: psk, saltInitiator: saltI, saltResponder: saltR
        )
        let key2 = SessionCrypto.deriveSessionKey(
            psk: psk, saltInitiator: saltI, saltResponder: saltR
        )
        XCTAssertEqual(
            key1.withUnsafeBytes { Data($0) },
            key2.withUnsafeBytes { Data($0) }
        )
    }

    func testDerivedKeyDiffersBySalt() {
        let psk = Data(repeating: 0xAB, count: 32)
        let saltA = Data(repeating: 0x01, count: 16)
        let saltB = Data(repeating: 0x02, count: 16)
        let key1 = SessionCrypto.deriveSessionKey(
            psk: psk, saltInitiator: saltA, saltResponder: saltB
        )
        let key2 = SessionCrypto.deriveSessionKey(
            psk: psk, saltInitiator: saltB, saltResponder: saltA
        )
        XCTAssertNotEqual(
            key1.withUnsafeBytes { Data($0) },
            key2.withUnsafeBytes { Data($0) }
        )
    }
}
