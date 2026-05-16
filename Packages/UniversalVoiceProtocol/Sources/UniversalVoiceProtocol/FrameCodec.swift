import Foundation

public struct HandshakeFrame: Equatable, Sendable {
    public let version: UInt16
    public let salt: Data

    public init(version: UInt16 = ProtocolVersion.current, salt: Data) {
        precondition(salt.count == SessionCrypto.saltLength, "salt must be 16 bytes")
        self.version = version
        self.salt = salt
    }
}

public enum HandshakeError: Error, Equatable {
    case shortFrame
    case badMagic
    case unsupportedVersion(UInt16)
}

public enum HandshakeCodec {
    public static let frameSize = 4 + 2 + SessionCrypto.saltLength

    public static func encode(_ frame: HandshakeFrame) -> Data {
        var out = Data(capacity: frameSize)
        out.append(contentsOf: ProtocolVersion.magic)
        out.append(UInt8((frame.version >> 8) & 0xFF))
        out.append(UInt8(frame.version & 0xFF))
        out.append(frame.salt)
        return out
    }

    public static func decode(_ data: Data) throws -> HandshakeFrame {
        guard data.count == frameSize else { throw HandshakeError.shortFrame }
        let bytes = Array(data)
        guard Array(bytes[0..<4]) == ProtocolVersion.magic else {
            throw HandshakeError.badMagic
        }
        let version = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
        guard version == ProtocolVersion.current else {
            throw HandshakeError.unsupportedVersion(version)
        }
        let salt = Data(bytes[6..<frameSize])
        return HandshakeFrame(version: version, salt: salt)
    }
}
