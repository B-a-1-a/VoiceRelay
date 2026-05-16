import XCTest
@testable import UniversalVoiceProtocol

final class WireFormatTests: XCTestCase {
    func testTextEncodesSnakeCaseKeys() throws {
        let payload = TextPayload(
            segmentId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            content: "hi",
            isFinalUtterance: true
        )
        let data = try MessageCodec.encode(.text(payload))
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"segment_id\""))
        XCTAssertTrue(json.contains("\"is_final_utterance\""))
        XCTAssertTrue(json.contains("\"type\":\"text\""))
    }

    func testTextRoundTrip() throws {
        let payload = TextPayload(
            segmentId: UUID(),
            content: "Push to staging.",
            isFinalUtterance: true
        )
        let data = try MessageCodec.encode(.text(payload))
        XCTAssertEqual(try MessageCodec.decode(data), .text(payload))
    }

    func testPingEncoding() throws {
        let data = try MessageCodec.encode(.ping)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"type\":\"ping\""))
        XCTAssertEqual(try MessageCodec.decode(data), .ping)
    }

    func testContextRequestEncoding() throws {
        let data = try MessageCodec.encode(.contextRequest)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"type\":\"context_request\""))
        XCTAssertEqual(try MessageCodec.decode(data), .contextRequest)
    }

    func testContextResponseRoundTrip() throws {
        let payload = ContextPayload(
            focusedBundleId: "com.tinyspeck.slackmacgap",
            focusedAppName: "Slack"
        )
        let data = try MessageCodec.encode(.contextResponse(payload))
        XCTAssertEqual(try MessageCodec.decode(data), .contextResponse(payload))
    }

    func testContextResponseNilFields() throws {
        let payload = ContextPayload(focusedBundleId: nil, focusedAppName: nil)
        let data = try MessageCodec.encode(.contextResponse(payload))
        XCTAssertEqual(try MessageCodec.decode(data), .contextResponse(payload))
    }
}
