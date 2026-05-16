import Foundation
@preconcurrency import AVFoundation
import UniversalVoiceProtocol

@MainActor
@Observable
final class DictationSession {
    enum Phase: Equatable, Sendable {
        case idle
        case preparing
        case recording
        case cleaning
        case sending
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var liveTranscript: String = ""
    private(set) var finalizedTranscript: String = ""
    private(set) var connection: Client.ClientState = .idle
    private(set) var cleanupFallbackBannerShown: Bool = false
    private(set) var pairedDevice: PairingPayload?

    private let audioCapture = AudioCapture()
    private let transcriber = Transcriber()
    private let cleanup = Cleanup()
    private let client = Client()
    private let liveActivity = LiveActivityHost()
    private let pairingStore = PairingStore()
    private var captureTask: Task<Void, Never>?

    init() {
        DictationCoordinator.shared.register(session: self)
        loadPairing()
        Task { await self.observeConnection() }
        Task { await self.cleanup.warmUp() }
    }

    func loadPairing() {
        pairedDevice = try? pairingStore.load()
    }

    func setPairing(_ payload: PairingPayload) {
        do {
            try pairingStore.save(payload)
            pairedDevice = payload
        } catch {
            phase = .error("Failed to save pairing: \(error.localizedDescription)")
        }
    }

    func clearPairing() {
        try? pairingStore.clear()
        pairedDevice = nil
    }

    func start() async {
        switch phase {
        case .idle, .error:
            break
        default:
            return
        }

        guard let pairing = pairedDevice else {
            phase = .error("Not paired with a Mac yet. Open Settings → Pair Mac.")
            return
        }

        phase = .preparing
        liveTranscript = ""
        finalizedTranscript = ""
        await liveActivity.startIfNeeded()
        await liveActivity.update(phase: .preparing, partialText: "")

        do {
            try await client.connect(to: pairing)
        } catch {
            await liveActivity.update(phase: .error, partialText: "Helper unreachable")
            await liveActivity.end()
            phase = .error("Helper unreachable: \(error.localizedDescription)")
            return
        }

        let format: AVAudioFormat
        do {
            format = try await transcriber.prepare()
        } catch {
            await liveActivity.update(phase: .error, partialText: "Speech setup failed")
            await liveActivity.end()
            phase = .error("Speech setup failed: \(error.localizedDescription)")
            return
        }

        do {
            try await transcriber.start(
                onSegment: { [weak self] segment in
                    Task { @MainActor [weak self] in
                        await self?.handleSegment(segment)
                    }
                },
                onSilence: { [weak self] in
                    Task { @MainActor [weak self] in
                        await self?.stop()
                    }
                }
            )
        } catch {
            phase = .error("Transcriber failed: \(error.localizedDescription)")
            return
        }

        let stream: AsyncStream<AVAudioPCMBuffer>
        do {
            stream = try audioCapture.start(outputFormat: format)
        } catch {
            await transcriber.stop()
            phase = .error("Audio capture failed: \(error.localizedDescription)")
            return
        }

        phase = .recording
        await liveActivity.update(phase: .recording, partialText: "")

        captureTask = Task.detached { [transcriber] in
            for await buffer in stream {
                await transcriber.feed(buffer: buffer)
            }
        }
    }

    func stop() async {
        guard phase == .recording else { return }
        phase = .cleaning
        await liveActivity.update(phase: .cleaning, partialText: finalizedTranscript)
        audioCapture.stop()
        captureTask?.cancel()
        captureTask = nil

        await transcriber.stop()

        let rawText = finalizedTranscript.isEmpty
            ? liveTranscript
            : finalizedTranscript
        guard !rawText.isEmpty else {
            await liveActivity.end()
            phase = .idle
            return
        }

        let cleaned: String
        let availability = await cleanup.availability()
        switch availability {
        case .available:
            do {
                cleaned = try await cleanup.clean(rawText)
            } catch {
                cleaned = rawText
            }
        case .unavailable:
            cleaned = rawText
            cleanupFallbackBannerShown = true
        }

        phase = .sending
        await liveActivity.update(phase: .sending, partialText: cleaned)
        do {
            try await client.send(.text(TextPayload(
                segmentId: UUID(),
                content: cleaned,
                isFinalUtterance: true
            )))
        } catch {
            await liveActivity.update(phase: .error, partialText: "Send failed")
            await liveActivity.end()
            phase = .error("Send failed: \(error.localizedDescription)")
            return
        }
        await liveActivity.end()
        phase = .idle
    }

    private func handleSegment(_ segment: TranscriptSegment) async {
        if segment.isVolatile {
            liveTranscript = segment.text
        } else {
            finalizedTranscript = appendFinal(finalizedTranscript, with: segment.text)
            liveTranscript = ""
        }
        let visible = finalizedTranscript.isEmpty ? liveTranscript : (finalizedTranscript + " " + liveTranscript)
        await liveActivity.update(phase: .recording, partialText: visible)
    }

    private func appendFinal(_ existing: String, with addition: String) -> String {
        let trimmed = addition.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return existing }
        if existing.isEmpty { return trimmed }
        return existing + " " + trimmed
    }

    private func observeConnection() async {
        for await state in await client.observe() {
            await MainActor.run { self.connection = state }
        }
    }
}
