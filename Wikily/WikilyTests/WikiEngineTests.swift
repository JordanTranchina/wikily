import Testing
@testable import Wikily

/// Port of `src/lib/wiki/wiki-engine.test.ts`.
///
/// Exercises the whole offline pipeline — parse markdown, build a TF-IDF index,
/// match a live transcript window — and asserts the spec's headline acceptance
/// criterion: the "Becky promotion" utterance resolves the correct local page,
/// above the proactive-trigger threshold, with no network and no audio stack.
///
/// The fixtures are copied verbatim from the TypeScript suite so a divergence
/// between the two engines shows up as a failure here rather than as a
/// mysterious behaviour change in the app.
struct WikiEngineTests {

    // MARK: - Fixtures

    static let files: [RawWikiFile] = [
        RawWikiFile(
            path: "/wiki/becky-promotion.md",
            name: "Project: Becky Promotion Campaign",
            content: """
            ---
            title: "Project: Becky Promotion Campaign"
            status: "In Progress (Deployment phase)"
            aliases: ["Becky promotion", "Becky campaign"]
            tags: [marketing, campaign, becky]
            notion: "https://notion.so/becky-promotion"
            ---

            # Project: Becky Promotion Campaign

            Latest Update: Visual assets approved by design team yesterday. Launch scheduled for next Tuesday.

            Key Blocker: None (previously waiting on design asset approval, resolved).

            Summary: Marketing push for the Becky product line. Deployment phase underway.

            """
        ),
        RawWikiFile(
            path: "/wiki/oauth-sandbox.md",
            name: "OAuth Redirect URI Setup",
            content: """
            ---
            title: "OAuth Redirect URI (Sandbox)"
            tags: [oauth, sandbox, auth]
            ---

            # OAuth Redirect URI (Sandbox)

            To configure the OAuth redirect URI for the Sandbox environment, set it to
            https://sandbox.example.com/oauth/callback in your app settings.

            """
        ),
        RawWikiFile(
            path: "/wiki/billing.md",
            name: "Billing & Invoices",
            content: """
            ---
            title: "Billing and Invoices"
            tags: [billing, payments]
            ---

            # Billing and Invoices

            How to view invoices and update payment methods.

            """
        ),
        // No frontmatter — title must fall back to the first H1.
        RawWikiFile(
            path: "/wiki/no-frontmatter.md",
            name: "no-frontmatter",
            content: """
            # Password Reset Flow

            Walk the customer through resetting their password from the login screen.

            """
        ),
    ]

    static let documents = files.map(MarkdownParser.parse)
    static let index = WikiIndexBuilder.build(documents)

    /// The proactive gate the overlay uses; matches the settings default range.
    static let threshold = 0.3

    static func document(_ id: String) -> WikiDocument {
        documents.first { $0.id == id }!
    }

    // MARK: - Parsing

    @Test func readsFrontmatterTitleStatusAliasesTagsAndNotionLink() {
        let becky = Self.document("/wiki/becky-promotion.md")
        #expect(becky.title == "Project: Becky Promotion Campaign")
        #expect(becky.status?.contains("In Progress") == true)
        #expect(becky.aliases.contains("Becky promotion"))
        #expect(becky.tags.contains("marketing"))
        #expect(becky.tags.contains("becky"))
        #expect(becky.links.contains { $0.url.contains("notion.so") })
    }

    @Test func extractsLatestUpdateAndKeyBlockerLines() {
        let becky = Self.document("/wiki/becky-promotion.md")
        #expect(becky.latestUpdate?.isEmpty == false)
        #expect(becky.latestUpdate?.contains("approved") == true)
        #expect(becky.blocker?.isEmpty == false)
    }

    @Test func fallsBackToFirstH1WhenNoFrontmatterTitle() {
        #expect(Self.document("/wiki/no-frontmatter.md").title == "Password Reset Flow")
    }

    @Test func onlyRealMarkdownAndFrontmatterLinksBecomeQuickLinks() {
        let oauth = Self.document("/wiki/oauth-sandbox.md")
        // The sandbox callback URL is bare text, not a markdown link, so it must
        // not appear as a quick link.
        #expect(oauth.links.allSatisfy { $0.url.hasPrefix("http") })
        #expect(!oauth.links.contains { $0.url.contains("sandbox.example.com") })
    }

    @Test func parsesBlockListFrontmatter() {
        let parsed = MarkdownParser.parseFrontmatter("""
        title: Block List Page
        aliases:
          - first alias
          - "second alias"
        """)
        #expect(parsed["title"]?.singleValue == "Block List Page")
        #expect(parsed["aliases"].arrayValue == ["first alias", "second alias"])
    }

    // MARK: - Matching

    @Test func resolvesBeckyPromotionQueryAboveThreshold() throws {
        let matches = WikiMatcher.match(
            index: Self.index,
            transcript: "How are you progressing with the Becky promotion?"
        )
        let top = try #require(matches.first)
        #expect(top.document.id == "/wiki/becky-promotion.md")
        #expect(top.score >= Self.threshold)
        // The proper-noun hit drives the "Matched: …" line on the card.
        #expect(!top.matchedEntities.isEmpty)
    }

    @Test func resolvesOAuthQuestionWithNoExactTitleMatch() throws {
        let matches = WikiMatcher.match(
            index: Self.index,
            transcript: "We are having trouble setting up the OAuth redirect URI for our Sandbox environment."
        )
        let top = try #require(matches.first)
        #expect(top.document.id == "/wiki/oauth-sandbox.md")
        #expect(top.score >= Self.threshold)
    }

    @Test func doesNotFalselyTriggerOnSmallTalk() {
        let matches = WikiMatcher.match(
            index: Self.index,
            transcript: "Did you watch the game last night? Crazy weather too."
        )
        #expect(matches.first == nil || matches[0].score < Self.threshold)
    }

    @Test func exactEntityHitOutranksPurelyLexicalOverlap() {
        // "billing" is a tag and title token on the billing page, but the
        // transcript names the Becky campaign explicitly — the entity boost must win.
        let matches = WikiMatcher.match(
            index: Self.index,
            transcript: "Quick billing question, but first: any update on the Becky campaign?"
        )
        #expect(matches.first?.document.id == "/wiki/becky-promotion.md")
    }

    @Test func returnsNothingForEmptyTranscriptOrEmptyIndex() {
        #expect(WikiMatcher.match(index: Self.index, transcript: "   ").isEmpty)
        #expect(WikiMatcher.match(index: WikiIndexBuilder.build([]), transcript: "anything").isEmpty)
    }

    @Test func respectsTopK() {
        let matches = WikiMatcher.match(
            index: Self.index,
            transcript: "billing invoice oauth sandbox becky promotion password reset",
            options: .init(topK: 2)
        )
        #expect(matches.count <= 2)
    }

    @Test func rankingIsDeterministicAcrossRuns() {
        // Guards the id tiebreak: dictionary iteration order varies per process,
        // so without it equally-scored documents could reorder between runs.
        let transcript = "billing invoice oauth sandbox becky promotion password reset"
        let first = WikiMatcher.match(index: Self.index, transcript: transcript).map(\.document.id)
        for _ in 0..<20 {
            let again = WikiMatcher.match(index: Self.index, transcript: transcript).map(\.document.id)
            #expect(again == first)
        }
    }

    // MARK: - Tokenizer

    @Test func tokenizerDropsStopwordsShortAndNumericTokens() {
        let tokens = Tokenizer.tokenize("The 2024 OAuth redirect URI is a big deal, um, okay?")
        #expect(!tokens.contains("the"))
        #expect(!tokens.contains("um"))
        #expect(!tokens.contains("okay"))
        #expect(!tokens.contains("2024"))
        #expect(!tokens.contains("a"))
        #expect(tokens.contains("oauth"))
        #expect(tokens.contains("redirect"))
        #expect(tokens.contains("uri"))
    }

    // MARK: - Hashing

    @Test func stableHashIsDeterministicAndDiffersForDifferentInput() {
        #expect(StableHash.string("becky promotion") == StableHash.string("becky promotion"))
        #expect(StableHash.string("becky promotion") != StableHash.string("oauth sandbox"))
    }

    @Test func stableHashNeverLeaksSourceTextAndStaysShortHex() {
        let hash = StableHash.string("client asked about the sandbox oauth redirect uri")
        #expect(hash.count == 8)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(!hash.contains("sandbox"))
    }

    @Test func stableHashMatchesTheTypeScriptImplementation() {
        // FNV-1a 32-bit over UTF-16, computed by src/lib/wiki/hash.ts. Pinning
        // known values here is what makes the two engines provably identical
        // rather than merely similar.
        #expect(StableHash.string("") == "811c9dc5")
        #expect(StableHash.string("a") == "e40c292c")
        #expect(StableHash.string("foobar") == "bf9cf968")
    }

    @Test func contentHashIsStableAcrossCallsAndSixteenHexDigits() {
        // Must not use Swift's per-process-seeded Hasher, or the incremental
        // re-scan cache would miss on every launch.
        let hash = StableHash.content("# Page\n\nSome content.")
        #expect(hash == StableHash.content("# Page\n\nSome content."))
        #expect(hash != StableHash.content("# Page\n\nDifferent content."))
        #expect(hash.count == 16)
    }
}
