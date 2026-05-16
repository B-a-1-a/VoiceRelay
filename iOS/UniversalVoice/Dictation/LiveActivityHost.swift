import Foundation
@preconcurrency import ActivityKit

@MainActor
final class LiveActivityHost {
    private var activity: Activity<DictationAttributes>?
    private var startedAt: Date?
    private var refreshTask: Task<Void, Never>?

    func adopt() {
        if activity == nil {
            activity = Activity<DictationAttributes>.activities.first
        }
        if startedAt == nil {
            startedAt = Date()
        }
        startRefresh()
    }

    func startIfNeeded() async {
        if let existing = Activity<DictationAttributes>.activities.first {
            activity = existing
            startedAt = Date()
            startRefresh()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity<DictationAttributes>.request(
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
            startedAt = Date()
            startRefresh()
        } catch {
            // Best-effort.
        }
    }

    func update(phase: DictationPhaseLabel, partialText: String) async {
        guard let activity else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt ?? Date()))
        await activity.update(
            ActivityContent(
                state: DictationAttributes.ContentState(
                    partialText: partialText,
                    phaseRaw: phase.rawValue,
                    elapsedSeconds: elapsed
                ),
                staleDate: nil
            )
        )
    }

    func end() async {
        refreshTask?.cancel()
        refreshTask = nil
        let final: ActivityContent<DictationAttributes.ContentState>? = {
            guard let activity else { return nil }
            return ActivityContent(state: activity.content.state, staleDate: nil)
        }()
        await activity?.end(final, dismissalPolicy: .immediate)
        activity = nil
        startedAt = nil
    }

    private func startRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await self.touchElapsed()
            }
        }
    }

    private func touchElapsed() async {
        guard let activity, let startedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let state = activity.content.state
        guard state.elapsedSeconds != elapsed else { return }
        await activity.update(
            ActivityContent(
                state: DictationAttributes.ContentState(
                    partialText: state.partialText,
                    phaseRaw: state.phaseRaw,
                    elapsedSeconds: elapsed
                ),
                staleDate: nil
            )
        )
    }
}
