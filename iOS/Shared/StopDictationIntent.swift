import AppIntents

struct StopDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let description = IntentDescription("Stop the in-progress dictation and send the cleaned transcript.")

    init() {}

    func perform() async throws -> some IntentResult {
        // Write a sentinel to the shared store; the running app observes via
        // Darwin notification and tears down the recording.
        AppGroup.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "stopRequest")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroup.stopRequestDarwinNotification as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}
