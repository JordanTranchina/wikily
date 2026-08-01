import Foundation

/// Lightweight tokenizer for the local matching engine.
///
/// Port of `src/lib/wiki/tokenize.ts`. English stopword removal plus simple
/// normalisation — no linguistic analysis, deliberately. The stopword list
/// includes conversational filler ("um", "yeah", "okay") because the input is a
/// live call transcript, not written prose.
enum Tokenizer {
    static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "being", "but", "by",
        "can", "could", "did", "do", "does", "doing", "for", "from", "had", "has",
        "have", "having", "he", "her", "here", "hers", "him", "his", "how", "i",
        "if", "in", "into", "is", "it", "its", "just", "me", "my", "no", "not",
        "of", "on", "or", "our", "out", "over", "she", "so", "some", "than", "that",
        "the", "their", "them", "then", "there", "these", "they", "this", "to",
        "too", "up", "us", "very", "was", "we", "were", "what", "when", "where",
        "which", "while", "who", "why", "will", "with", "would", "you", "your",
        // conversational filler common in live transcripts
        "um", "uh", "okay", "ok", "yeah", "hey", "hi", "hello", "thanks", "thank",
        "like", "know", "going", "get", "got", "want", "need", "lets", "let",
    ]

    /// Characters stripped to whitespace before splitting, matching the
    /// TypeScript `[`*_>#~|\[\]()]` class.
    private static let strippedPunctuation: Set<Character> = [
        "`", "*", "_", ">", "#", "~", "|", "[", "]", "(", ")",
    ]

    /// Split text into normalised, stopword-filtered tokens.
    ///
    /// Keeps tokens of 2+ characters that are not stopwords and not purely
    /// numeric. Splitting is on anything outside `[a-z0-9]`, so this is
    /// intentionally ASCII-only, same as the original.
    static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var tokens: [String] = []
        var current = ""

        func flush() {
            defer { current = "" }
            guard current.count >= 2 else { return }
            guard !stopwords.contains(current) else { return }
            // Drop purely numeric tokens (years, ticket numbers, amounts).
            guard current.contains(where: { !$0.isNumber }) else { return }
            tokens.append(current)
        }

        for character in text.lowercased() {
            if strippedPunctuation.contains(character) {
                flush()
            } else if character.isASCII, character.isLetter || character.isNumber {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()

        return tokens
    }

    /// Count term frequencies for a token list.
    static func termFrequencies(_ tokens: [String]) -> [String: Double] {
        var frequencies: [String: Double] = [:]
        for token in tokens {
            frequencies[token, default: 0] += 1
        }
        return frequencies
    }
}
