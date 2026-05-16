import AppIntents
import ActivityKit

struct StartDictationIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Record your voice and type the cleaned transcript on your paired Mac.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // Request the Live Activity before returning so the OS grants the
        // background-audio assertion bound to the activity.
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                _ = try Activity<DictationAttributes>.request(
                    attributes: DictationAttributes(),
                    content: ActivityContent(
                        state: DictationAttributes.ContentState(
                            partialText: "",
                            phaseRaw: DictationPhaseLabel.preparing.rawValue,
                            elapsedSeconds: 0
                        ),
                        staleDate: nil
                    ),
                    pushType: nil
                )
            } catch {
                // Best-effort: continue even if Live Activity request fails.
            }
        }

        DictationCoordinator.shared.requestStart()
        return .result()
    }
}
