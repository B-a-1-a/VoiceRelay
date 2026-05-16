import Foundation

enum HelperConfig {
    static let listenPort: UInt16 = {
        if let raw = ProcessInfo.processInfo.environment["VR_LISTEN_PORT"], let p = UInt16(raw) {
            return p
        }
        return 7842
    }()

    static let typingCharactersPerSecond: Double = 600
}
