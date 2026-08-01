import Foundation

/// A pre-computed TF-IDF search index over a set of documents.
///
/// Port of `src/lib/wiki/index-engine.ts`.
struct WikiIndex: Sendable {
    var documents: [WikiDocument]
    /// Inverse document frequency per token.
    var idf: [String: Double]
    /// L2-normalised tf-idf vector per document id.
    var vectors: [String: [String: Double]]
    /// Lowercased entity/title/alias/tag phrases mapped to document ids.
    var entityMap: [String: [String]]
    var stats: Stats

    struct Stats: Sendable, Equatable {
        var documentCount: Int
        var tokenCount: Int
    }

    static let empty = WikiIndex(
        documents: [],
        idf: [:],
        vectors: [:],
        entityMap: [:],
        stats: Stats(documentCount: 0, tokenCount: 0)
    )
}

/// Builds the local TF-IDF index.
///
/// Field weighting: titles, aliases, tags and headings carry far more signal
/// than body prose, so their tokens are counted multiple times when
/// accumulating term frequencies. Document vectors are L2-normalised, which
/// reduces matching to a plain dot product (see `WikiMatcher`).
enum WikiIndexBuilder {

    /// How many times a token counts, by the field it came from.
    enum FieldWeight {
        static let title = 5.0
        static let aliases = 5.0
        static let tags = 4.0
        static let headings = 2.0
        static let summary = 2.0
        static let status = 2.0
        static let latestUpdate = 2.0
        static let body = 1.0
    }

    static func build(_ documents: [WikiDocument]) -> WikiIndex {
        var documentFrequency: [String: Double] = [:]
        var rawTermFrequency: [String: [String: Double]] = [:]
        var entityMap: [String: [String]] = [:]

        for document in documents {
            let frequencies = weightedTokens(document)
            rawTermFrequency[document.id] = frequencies
            for token in frequencies.keys {
                documentFrequency[token, default: 0] += 1
            }
            for phrase in entities(for: document) {
                entityMap[phrase, default: []].append(document.id)
            }
        }

        let n = Double(max(documents.count, 1))
        var idf: [String: Double] = [:]
        for (token, frequency) in documentFrequency {
            // Smoothed idf — always positive, so a term shared by every document
            // still contributes a little rather than zeroing out.
            idf[token] = log((n + 1) / (frequency + 1)) + 1
        }

        var vectors: [String: [String: Double]] = [:]
        for document in documents {
            let frequencies = rawTermFrequency[document.id] ?? [:]
            var vector: [String: Double] = [:]
            var norm = 0.0
            for (token, frequency) in frequencies {
                let weight = (1 + log(frequency)) * (idf[token] ?? 1)
                vector[token] = weight
                norm += weight * weight
            }
            norm = norm.squareRoot()
            if norm == 0 { norm = 1 }
            for token in vector.keys {
                vector[token]! /= norm
            }
            vectors[document.id] = vector
        }

        return WikiIndex(
            documents: documents,
            idf: idf,
            vectors: vectors,
            entityMap: entityMap,
            stats: WikiIndex.Stats(
                documentCount: documents.count,
                tokenCount: idf.count
            )
        )
    }

    /// Accumulate weighted term frequencies across a document's fields.
    static func weightedTokens(_ document: WikiDocument) -> [String: Double] {
        var frequencies: [String: Double] = [:]

        func add(_ text: String?, weight: Double) {
            guard let text, !text.isEmpty else { return }
            for token in Tokenizer.tokenize(text) {
                frequencies[token, default: 0] += weight
            }
        }

        add(document.title, weight: FieldWeight.title)
        for alias in document.aliases { add(alias, weight: FieldWeight.aliases) }
        for tag in document.tags { add(tag, weight: FieldWeight.tags) }
        for heading in document.headings { add(heading, weight: FieldWeight.headings) }
        add(document.summary, weight: FieldWeight.summary)
        add(document.status, weight: FieldWeight.status)
        add(document.latestUpdate, weight: FieldWeight.latestUpdate)
        add(document.body, weight: FieldWeight.body)

        return frequencies
    }

    /// Phrases that should resolve directly to a document — the strongest
    /// available signal that a caller is talking about this exact page.
    static func entities(for document: WikiDocument) -> [String] {
        var phrases = OrderedUnique<String>()

        func push(_ phrase: String) {
            let normalised = phrase.trimmed.lowercased()
            guard normalised.count >= 3 else { return }
            phrases.insert(normalised)
        }

        push(document.title)
        document.aliases.forEach(push)
        for tag in document.tags {
            push(tag.replacing(#/[-_\/]/#, with: " "))
        }
        return phrases.values
    }
}
