import Foundation
import FoundationModels

actor Cleanup {
    enum CleanupError: Error {
        case modelUnavailable(reason: String)
    }

    enum Availability: Sendable {
        case available
        case unavailable(String)
    }

    private let instructions: String = """
    You are a dictation cleanup assistant. The user dictated text aloud. Your job:

    - Remove filler words: um, uh, like, you know, sort of, I mean, kind of.
    - Fix obvious grammar and punctuation. Add commas, periods, and question marks.
    - Preserve the speaker's intent, tone, and word choice. Do not paraphrase.
    - Do not add new content. Do not answer questions in the text.
    - Do not include preamble like "Here is the cleaned text:" — return only the cleaned text.
    - Keep code identifiers, command names, and proper nouns intact, including casing.
    - If the input is already clean, return it unchanged.
    """

    private var session: LanguageModelSession?

    func warmUp() async {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else { return }
        let session = LanguageModelSession(
            model: .default,
            tools: [],
            instructions: instructions
        )
        self.session = session
        // Dispatch a tiny prompt to pre-load the model.
        _ = try? await session.respond(to: "ready")
    }

    func availability() -> Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(String(describing: reason))
        }
    }

    func clean(_ rawText: String) async throws -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let availability = SystemLanguageModel.default.availability
        if case .unavailable(let reason) = availability {
            throw CleanupError.modelUnavailable(reason: String(describing: reason))
        }

        let session = self.session ?? LanguageModelSession(
            model: .default,
            tools: [],
            instructions: instructions
        )
        self.session = session

        let response = try await session.respond(to: trimmed)
        let raw = response.content
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        session = nil
    }
}
