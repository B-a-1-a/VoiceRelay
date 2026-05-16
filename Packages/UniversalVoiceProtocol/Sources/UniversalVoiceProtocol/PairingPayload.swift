import Foundation

/// Encoded into the pairing QR code shown by the Mac helper. Scanned by the
/// iPhone, then both `deviceUUID` and `psk` are persisted in the iPhone's
/// keychain alongside `serviceName` (used for mDNS lookup).
public struct PairingPayload: Codable, Equatable, Sendable {
    public let serviceName: String
    public let deviceUUID: String
    public let pskBase64: String
    public let port: UInt16
    public let hostHint: String?

    public init(
        serviceName: String,
        deviceUUID: String,
        pskBase64: String,
        port: UInt16,
        hostHint: String?
    ) {
        self.serviceName = serviceName
        self.deviceUUID = deviceUUID
        self.pskBase64 = pskBase64
        self.port = port
        self.hostHint = hostHint
    }

    public var pskData: Data? {
        Data(base64Encoded: pskBase64)
    }

    public func qrString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return "uv://" + data.base64EncodedString()
    }

    public static func parse(qrString: String) throws -> PairingPayload {
        let prefix = "uv://"
        guard qrString.hasPrefix(prefix) else {
            throw PairingPayloadError.badPrefix
        }
        let base64 = String(qrString.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: base64) else {
            throw PairingPayloadError.notBase64
        }
        return try JSONDecoder().decode(PairingPayload.self, from: data)
    }
}

public enum PairingPayloadError: Error, Equatable {
    case badPrefix
    case notBase64
}

public enum BonjourService {
    public static let type = "_universalvoice._tcp"
}
