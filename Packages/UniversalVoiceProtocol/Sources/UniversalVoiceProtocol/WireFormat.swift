import Foundation

public enum ProtocolVersion {
    public static let current: UInt16 = 1
    public static let magic: [UInt8] = [0x55, 0x56, 0x4F, 0x49]  // "UVOI"
}

public enum Message: Equatable, Sendable {
    case text(TextPayload)
    case ping
    case contextRequest
    case contextResponse(ContextPayload)
}

public struct TextPayload: Equatable, Sendable, Codable {
    public let segmentId: UUID
    public let content: String
    public let isFinalUtterance: Bool

    public init(segmentId: UUID, content: String, isFinalUtterance: Bool) {
        self.segmentId = segmentId
        self.content = content
        self.isFinalUtterance = isFinalUtterance
    }
}

public struct ContextPayload: Equatable, Sendable, Codable {
    public let focusedBundleId: String?
    public let focusedAppName: String?

    public init(focusedBundleId: String?, focusedAppName: String?) {
        self.focusedBundleId = focusedBundleId
        self.focusedAppName = focusedAppName
    }
}

extension Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum Kind: String, Codable {
        case text
        case ping
        case contextRequest = "context_request"
        case contextResponse = "context_response"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .text:
            let payload = try container.decode(TextPayload.self, forKey: .payload)
            self = .text(payload)
        case .ping:
            self = .ping
        case .contextRequest:
            self = .contextRequest
        case .contextResponse:
            let payload = try container.decode(ContextPayload.self, forKey: .payload)
            self = .contextResponse(payload)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let payload):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .ping:
            try container.encode(Kind.ping, forKey: .type)
        case .contextRequest:
            try container.encode(Kind.contextRequest, forKey: .type)
        case .contextResponse(let payload):
            try container.encode(Kind.contextResponse, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

public enum MessageCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public static func encode(_ message: Message) throws -> Data {
        try encoder.encode(message)
    }

    public static func decode(_ data: Data) throws -> Message {
        try decoder.decode(Message.self, from: data)
    }
}
