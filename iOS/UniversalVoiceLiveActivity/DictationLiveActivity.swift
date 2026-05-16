import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationAttributes.self) { context in
            DictationLockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopDictationIntent()) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.partialText.isEmpty
                         ? phaseLabel(context.state.phaseRaw)
                         : context.state.partialText)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(phaseLabel(context.state.phaseRaw))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(context.state.elapsedSeconds)s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text("\(context.state.elapsedSeconds)s")
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
            }
        }
    }

    private func phaseLabel(_ raw: String) -> String {
        switch DictationPhaseLabel(rawValue: raw) {
        case .preparing: return "Preparing"
        case .recording: return "Listening"
        case .cleaning: return "Cleaning"
        case .sending: return "Sending"
        case .error: return "Error"
        case .none: return raw.capitalized
        }
    }
}

struct DictationLockScreenView: View {
    let state: DictationAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
                Text(phaseLabel)
                    .font(.headline)
                Spacer()
                Text("\(state.elapsedSeconds)s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(intent: StopDictationIntent()) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            if !state.partialText.isEmpty {
                Text(state.partialText)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(3)
            } else {
                Text("Speak; your Mac will type.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var phaseLabel: String {
        switch DictationPhaseLabel(rawValue: state.phaseRaw) {
        case .preparing: return "Universal Voice — preparing"
        case .recording: return "Universal Voice — listening"
        case .cleaning: return "Universal Voice — cleaning"
        case .sending: return "Universal Voice — sending"
        case .error: return "Universal Voice — error"
        case .none: return "Universal Voice"
        }
    }
}
