import Foundation

/// Matches a live transcript window against the local wiki index.
///
/// Port of `src/lib/wiki/match-engine.ts`. Two signals combine:
///
///  1. **Cosine similarity** between the transcript's tf-idf vector and each
///     document vector — lexical overlap, standing in for semantic similarity.
///  2. **Exact entity hits** — a document's title, alias or tag appearing
///     verbatim in the transcript (e.g. "Becky promotion"). This is by far the
///     strongest signal that someone is talking about that specific page, and
///     it is additive so it can lift a document past one that merely shares
///     common vocabulary.
enum WikiMatcher {

    struct Options: Sendable {
        /// Maximum number of matches to return.
        var topK: Int = 3
        /// Additive boost for the first exact entity hit.
        var entityBoost: Double = 0.4
        /// Additional boost per entity hit beyond the first.
        var additionalEntityBoost: Double = 0.15

        init(topK: Int = 3, entityBoost: Double = 0.4, additionalEntityBoost: Double = 0.15) {
            self.topK = topK
            self.entityBoost = entityBoost
            self.additionalEntityBoost = additionalEntityBoost
        }
    }

    static func match(
        index: WikiIndex,
        transcript: String,
        options: Options = Options()
    ) -> [WikiMatch] {
        guard !transcript.trimmed.isEmpty, !index.documents.isEmpty else { return [] }

        let queryTokens = Tokenizer.tokenize(transcript)
        let queryVector = queryVector(index: index, tokens: queryTokens)
        let normalisedTranscript = normalisePhrase(transcript)

        // Exact entity hits, document id -> matched phrases.
        var entityHits: [String: OrderedUnique<String>] = [:]
        for (phrase, documentIDs) in index.entityMap {
            let needle = normalisePhrase(phrase)
            // The length floor keeps two-letter tags and similar noise from
            // matching almost every transcript.
            guard needle.count > 4, normalisedTranscript.contains(needle) else { continue }
            for id in documentIDs {
                entityHits[id, default: OrderedUnique<String>()].insert(phrase)
            }
        }

        var matches: [WikiMatch] = []
        for document in index.documents {
            let similarity = cosine(queryVector, index.vectors[document.id] ?? [:])
            let hits = entityHits[document.id]?.values ?? []
            let boost = hits.isEmpty
                ? 0
                : options.entityBoost + Double(hits.count - 1) * options.additionalEntityBoost
            let score = min(1, similarity + boost)
            guard score > 0 else { continue }
            matches.append(
                WikiMatch(document: document, score: score, matchedEntities: hits)
            )
        }

        // Sorted by score, then by id to break ties. The id tiebreak is a
        // deliberate addition: Swift's sort is not guaranteed stable, and
        // without it two equally-scored documents could swap places between
        // runs, making the overlay flicker between suggestions.
        matches.sort {
            $0.score == $1.score ? $0.document.id < $1.document.id : $0.score > $1.score
        }
        return Array(matches.prefix(options.topK))
    }

    // MARK: - Internals

    /// Normalise text for phrase matching: lowercased, non-alphanumerics
    /// collapsed to single spaces, and space-padded so `contains` only matches
    /// on word boundaries ("becky" must not match inside "beckys").
    static func normalisePhrase(_ text: String) -> String {
        let collapsed = text
            .lowercased()
            .replacing(#/[^a-z0-9]+/#, with: " ")
            .trimmed
        return " \(collapsed) "
    }

    /// Build an L2-normalised tf-idf query vector from the transcript window.
    static func queryVector(index: WikiIndex, tokens: [String]) -> [String: Double] {
        let frequencies = Tokenizer.termFrequencies(tokens)
        var vector: [String: Double] = [:]
        var norm = 0.0

        for (token, frequency) in frequencies {
            // A term in no document carries no discriminating power — skip it
            // rather than letting it inflate the norm and dilute real hits.
            guard let idf = index.idf[token] else { continue }
            let weight = (1 + log(frequency)) * idf
            vector[token] = weight
            norm += weight * weight
        }

        norm = norm.squareRoot()
        if norm == 0 { norm = 1 }
        for token in vector.keys {
            vector[token]! /= norm
        }
        return vector
    }

    /// Both vectors are already L2-normalised, so the dot product *is* the cosine.
    static func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        // Iterate the smaller vector; the transcript vector is usually far
        // smaller than a document's.
        let (small, large) = a.count < b.count ? (a, b) : (b, a)
        var dot = 0.0
        for (token, weight) in small {
            if let other = large[token] { dot += weight * other }
        }
        return dot
    }
}
