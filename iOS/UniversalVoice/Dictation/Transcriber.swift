import Foundation
import AVFoundation
import CoreMedia
import Speech

struct TranscriptSegment: Sendable {
    let id: UUID
    let text: String
    let isVolatile: Bool
}

actor Transcriber {
    enum TranscriberError: Error {
        case authorizationDenied
        case localeUnsupported
        case modelUnavailable
        case alreadyRunning
    }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private(set) var preferredFormat: AVAudioFormat?

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func prepare(locale: Locale = Locale(identifier: "en-US")) async throws -> AVAudioFormat {
        let auth = await Self.requestAuthorization()
        guard auth == .authorized else { throw TranscriberError.authorizationDenied }

        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriberError.localeUnsupported
        }

        let transcriber = SpeechTranscriber(
            locale: supported,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        let modules: [any SpeechModule] = [transcriber]
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }

        let formats = await transcriber.availableCompatibleAudioFormats
        guard let chosen = formats.first else {
            throw TranscriberError.modelUnavailable
        }
        self.transcriber = transcriber
        self.preferredFormat = chosen
        return chosen
    }

    func start(
        onSegment: @escaping @Sendable (TranscriptSegment) -> Void,
        onSilence: @escaping @Sendable () -> Void
    ) async throws {
        guard analyzer == nil else { throw TranscriberError.alreadyRunning }
        guard let transcriber else { throw TranscriberError.modelUnavailable }

        let stream = AsyncStream<AnalyzerInput>(bufferingPolicy: .unbounded) { continuation in
            self.inputContinuation = continuation
        }

        let analyzer = SpeechAnalyzer(
            inputSequence: stream,
            modules: [transcriber]
        )
        self.analyzer = analyzer

        resultsTask = Task.detached { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let volatile = await self?.isVolatile(result: result, analyzer: analyzer) ?? true
                    onSegment(TranscriptSegment(
                        id: UUID(),
                        text: text,
                        isVolatile: volatile
                    ))
                    await self?.resetSilenceTimer(onSilence: onSilence)
                }
            } catch {
                _ = error
            }
        }

        resetSilenceTimer(onSilence: onSilence)
    }

    private func isVolatile(result: SpeechTranscriber.Result, analyzer: SpeechAnalyzer) async -> Bool {
        guard let volatile = await analyzer.volatileRange else { return false }
        return result.range.end > volatile.start
    }

    func feed(buffer: AVAudioPCMBuffer) {
        guard let inputContinuation else { return }
        inputContinuation.yield(AnalyzerInput(buffer: buffer))
    }

    func stop() async {
        inputContinuation?.finish()
        inputContinuation = nil
        silenceTask?.cancel()
        silenceTask = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
    }

    private func resetSilenceTimer(onSilence: @escaping @Sendable () -> Void) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, self != nil else { return }
            onSilence()
        }
    }
}
