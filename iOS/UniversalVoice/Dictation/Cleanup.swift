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

    @Generable
    struct CleanedDictation {
        @Guide(description: "The user's dictated text with filler words removed and punctuation corrected. Plain text only — never a greeting, offer, apology, or meta-commentary, and never a question back to the user.")
        let text: String
    }

    private let instructions: String = """
    You clean up dictated speech. The input is a raw transcript of something the user said aloud. Return only their words — corrected, not answered.

    Rules:
    - Remove filler words: um, uh, like, you know, sort of, I mean, kind of.
    - Fix obvious grammar and add commas, periods, and question marks.
    - Preserve the speaker's intent, tone, and word choice. Do not paraphrase.
    - Do not add new content. Do not answer questions in the text.
    - Do not include preamble like "Here is the cleaned text:" — return only the cleaned text.
    - Keep code identifiers, command names, and proper nouns intact, including casing.
    - If the input is a single word, fragment, or empty, return it unchanged.
    - Never produce greetings, offers, or meta-commentary. Never ask the user to provide input.

    Examples:
      Input: "hello"
      Output: "hello"

      Input: "um what time is it"
      Output: "What time is it?"

      Input: "yeah so like push the staging branch please"
      Output: "Yeah, push the staging branch please."
    """

    private let suspiciousPhrases: [String] = [
        "i'm here to help",
        "i am here to help",
        "i'd be happy",
        "i would be happy",
        "please provide",
        "please go ahead",
        "sure!",
        "of course!",
        "here is the cleaned",
        "here's the cleaned",
        "as an ai",
        "let me know"
    ]

    func warmUp() async {
        guard case .available = SystemLanguageModel.default.availability else { return }
        let throwaway = LanguageModelSession(
            model: .default,
            tools: [],
            instructions: instructions
        )
        throwaway.prewarm()
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

        let session = LanguageModelSession(
            model: .default,
            tools: [],
            instructions: instructions
        )
        let options = GenerationOptions(temperature: 0.1)
        let response = try await session.respond(
            to: trimmed,
            generating: CleanedDictation.self,
            options: options
        )
        let cleaned = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitize(cleaned: cleaned, original: trimmed)
    }

    private func sanitize(cleaned: String, original: String) -> String {
        if cleaned.isEmpty { return original }
        let lower = cleaned.lowercased()
        for phrase in suspiciousPhrases where lower.contains(phrase) {
            return original
        }
        if cleaned.count > max(40, original.count * 3) {
            return original
        }
        return cleaned
    }
}
