import ActivityKit
import Foundation

struct DictationAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var partialText: String
        public var phaseRaw: String
        public var elapsedSeconds: Int

        public init(partialText: String, phaseRaw: String, elapsedSeconds: Int) {
            self.partialText = partialText
            self.phaseRaw = phaseRaw
            self.elapsedSeconds = elapsedSeconds
        }
    }

    public init() {}
}

enum DictationPhaseLabel: String, Sendable {
    case preparing
    case recording
    case cleaning
    case sending
    case error
}

enum AppGroup {
    static let identifier = "group.dev.balashukla.voicerelay"

    static let stopRequestDarwinNotification = "dev.balashukla.voicerelay.stopRequest"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
