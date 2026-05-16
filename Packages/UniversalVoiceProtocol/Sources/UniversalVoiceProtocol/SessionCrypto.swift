import Foundation
import CryptoKit

public enum SessionRole: Sendable {
    case initiator  // iPhone
    case responder  // Mac
}

public enum SessionError: Error, Equatable {
    case decryptionFailed
    case replayedNonce(seen: UInt64, last: UInt64)
    case wrongDirection
    case malformedFrame
    case counterOverflow
}

extension SessionCrypto {
    public static let keyLength = 32
    public static let pskLength = 32
    public static let saltLength = 16
    public static let nonceLength = 12
    public static let tagLength = 16
}

public struct SessionCrypto {
    private let key: SymmetricKey
    private let sendDir: UInt8
    private let recvDir: UInt8
    private var sendCounter: UInt64 = 0
    private var lastRecvCounter: UInt64 = 0
    private var hasReceived: Bool = false

    public init(key: SymmetricKey, role: SessionRole) {
        precondition(key.bitCount == Self.keyLength * 8, "session key must be 256-bit")
        self.key = key
        switch role {
        case .initiator:
            self.sendDir = 0x01
            self.recvDir = 0x02
        case .responder:
            self.sendDir = 0x02
            self.recvDir = 0x01
        }
    }

    /// HKDF-SHA256(ikm: PSK, salt: saltI ‖ saltR, info: "uv-v1-session", L: 32).
    public static func deriveSessionKey(
        psk: Data,
        saltInitiator: Data,
        saltResponder: Data
    ) -> SymmetricKey {
        precondition(psk.count == pskLength, "PSK must be 32 bytes")
        precondition(saltInitiator.count == saltLength, "salt must be 16 bytes")
        precondition(saltResponder.count == saltLength, "salt must be 16 bytes")
        let salt = saltInitiator + saltResponder
        let info = Data("uv-v1-session".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: psk),
            salt: salt,
            info: info,
            outputByteCount: keyLength
        )
    }

    public static func freshSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
        precondition(status == errSecSuccess, "random failure")
        return Data(bytes)
    }

    public static func freshPSK() -> Data {
        var bytes = [UInt8](repeating: 0, count: pskLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, pskLength, &bytes)
        precondition(status == errSecSuccess, "random failure")
        return Data(bytes)
    }

    /// nonce layout: [direction: 1][counter: 8 big-endian][padding: 3 zero bytes].
    private static func makeNonce(direction: UInt8, counter: UInt64) -> ChaChaPoly.Nonce {
        var bytes = [UInt8](repeating: 0, count: nonceLength)
        bytes[0] = direction
        bytes[1] = UInt8((counter >> 56) & 0xFF)
        bytes[2] = UInt8((counter >> 48) & 0xFF)
        bytes[3] = UInt8((counter >> 40) & 0xFF)
        bytes[4] = UInt8((counter >> 32) & 0xFF)
        bytes[5] = UInt8((counter >> 24) & 0xFF)
        bytes[6] = UInt8((counter >> 16) & 0xFF)
        bytes[7] = UInt8((counter >> 8) & 0xFF)
        bytes[8] = UInt8(counter & 0xFF)
        return try! ChaChaPoly.Nonce(data: bytes)
    }

    public mutating func seal(_ message: Message) throws -> Data {
        let plaintext = try MessageCodec.encode(message)
        guard sendCounter < UInt64.max else { throw SessionError.counterOverflow }
        let nonce = Self.makeNonce(direction: sendDir, counter: sendCounter)
        sendCounter &+= 1
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce)
        return box.combined
    }

    public mutating func open(_ frame: Data) throws -> Message {
        guard frame.count >= Self.nonceLength + Self.tagLength else {
            throw SessionError.malformedFrame
        }
        let nonceBytes = frame.prefix(Self.nonceLength)
        guard nonceBytes[nonceBytes.startIndex] == recvDir else {
            throw SessionError.wrongDirection
        }
        var counter: UInt64 = 0
        for i in 0..<8 {
            counter = (counter << 8) | UInt64(nonceBytes[nonceBytes.startIndex + 1 + i])
        }
        if hasReceived && counter <= lastRecvCounter {
            throw SessionError.replayedNonce(seen: counter, last: lastRecvCounter)
        }
        let box: ChaChaPoly.SealedBox
        do {
            box = try ChaChaPoly.SealedBox(combined: frame)
        } catch {
            throw SessionError.malformedFrame
        }
        let plaintext: Data
        do {
            plaintext = try ChaChaPoly.open(box, using: key)
        } catch {
            throw SessionError.decryptionFailed
        }
        lastRecvCounter = counter
        hasReceived = true
        return try MessageCodec.decode(plaintext)
    }
}
