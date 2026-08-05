import Foundation

/// Headless probe for the model backends.
///
/// Exists because unit tests can verify SSE parsing, availability mapping and
/// discovery timeouts without either backend ever producing a token — which is
/// exactly the state Phase 5 shipped in. Parsing tests passing while no model
/// has ever answered is the same shape of false confidence that let a broken
/// `SpeechAnalyzer` setup look healthy earlier in this project.
///
/// This actually generates. Run it with `--probe-models`.
enum ModelDiagnostics {

    static let argument = "--probe-models"
    static let askArgument = "--probe-ask"

    static func isRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(argument)
    }

    /// `--probe-ask <vault>` — exercise the grounded Q&A prompt against a real
    /// model and a real wiki page.
    static func askVaultPath(from arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: askArgument),
              arguments.indices.contains(index + 1)
        else { return nil }
        return (arguments[index + 1] as NSString).expandingTildeInPath
    }

    static func run() async {
        print("""

        Wikily model probe
        ──────────────────
        """)

        await probeApple()
        await probeLocalServers()
        print("")
    }

    // MARK: - Grounded Q&A

    /// Ask real questions of a real page through a real model.
    ///
    /// `GroundedPromptTests` asserts the prompt *says* the right things. Whether
    /// a small on-device model actually obeys "answer only from this page, and
    /// say so when it can't" is a different claim, and the only way to check it
    /// is to ask. The third question below is the one that matters: it has no
    /// answer in the page, and a model that invents one would be dangerous here,
    /// because the user reads these answers aloud to a customer.
    static func probeAsk(vaultPath: String) async {
        print("""

        Wikily grounded Q&A probe
        ─────────────────────────
        """)

        let service = AppleFoundationModelService()
        let availability = await service.availability()
        guard availability.isAvailable else {
            print("\nApple on-device model unavailable: \(availability.message ?? "no reason")\n")
            return
        }

        let page: WikiDocument
        do {
            let scan = try WikiScanner.scan(directory: vaultPath)
            let documents = scan.files.map(MarkdownParser.parse)
            guard let becky = documents.first(where: { $0.title.contains("Becky") })
                ?? documents.first
            else {
                print("\nNo pages in \(vaultPath)\n")
                return
            }
            page = becky
        } catch {
            print("\nCould not read vault: \(error.localizedDescription)\n")
            return
        }

        let transcript = [
            TranscriptSegment(
                text: "Hey, quick question — where did we land on the Becky promotion?",
                source: .system,
                startTime: 0
            ),
            TranscriptSegment(text: "Let me pull that up.", source: .microphone, startTime: 5),
        ]

        print("\nPage: \(page.title)")
        print("Status on page: \(page.status ?? "none")\n")

        let questions: [(label: String, question: String)] = [
            ("answerable from the page", "What's the current status?"),
            ("needs the call context", QuickAction.whatToSay.prompt),
            // Deliberately unanswerable. The page says nothing about pricing.
            ("NOT in the page", "What discount percentage did we agree for this campaign?"),
        ]

        for (label, question) in questions {
            let prompt = GroundedPrompt.build(
                question: question,
                page: page,
                transcript: transcript
            )
            print("Q (\(label)): \(question)")

            var answer = ""
            do {
                for try await delta in service.stream(
                    prompt: prompt.user,
                    systemPrompt: prompt.system
                ) {
                    answer += delta
                }
            } catch {
                print("  FAILED: \(error.localizedDescription)\n")
                continue
            }
            print("A: \(answer.trimmingCharacters(in: .whitespacesAndNewlines))\n")
        }

        print("""
        The third answer is the one to read carefully. If it states a discount
        figure, the grounding is not holding and the system prompt needs work.

        """)
    }

    // MARK: - Apple on-device

    private static func probeApple() async {
        let service = AppleFoundationModelService()
        print("\nApple on-device (FoundationModels)")

        let availability = await service.availability()
        guard availability.isAvailable else {
            print("  unavailable: \(availability.message ?? "no reason given")")
            return
        }
        print("  available")

        // The real check. Availability reporting has its own tests; whether a
        // token ever comes out does not.
        await generate(
            with: service,
            prompt: "Reply with exactly the word: ready"
        )

        // A longer answer, to measure streaming granularity rather than mere
        // correctness. One delta means the HUD will pop the whole reply into
        // place; many means it can type it out. That is a visible product
        // difference and it is not something a parsing test can tell you.
        await generate(
            with: service,
            prompt: "In three sentences, explain what a customer support wiki is for."
        )
    }

    // MARK: - Local servers

    private static func probeLocalServers() async {
        print("\nLocal model servers")

        let found = await LocalServerDiscovery.probeAll()
        guard !found.isEmpty else {
            print("""
                  none reachable on :11434 (Ollama), :1234 (LM Studio) or :8080 (llama-server).
                  Start one and re-run to exercise the streaming path against a real model.
              """)
            return
        }

        for server in found {
            print("  \(server.displayName) at \(server.baseURL) — \(server.models.count) model(s)")
            for model in server.models.prefix(10) {
                print("    · \(model)")
            }

            guard let first = server.models.first else {
                print("    (no models to generate with)")
                continue
            }
            let service = LocalServerModelService(
                baseURL: server.baseURL,
                modelID: first
            )
            await generate(
                with: service,
                prompt: "Reply with exactly the word: ready"
            )
        }
    }

    // MARK: - Shared

    /// Stream a short completion and report what actually arrived.
    ///
    /// Reports the delta count as well as the text: a backend that returns the
    /// whole answer as one chunk still "works", but it means the HUD will pop
    /// rather than type, which is worth knowing before wiring up the UI.
    private static func generate(with service: some LanguageModelService, prompt: String) async {
        let started = Date()
        var deltas = 0
        var text = ""

        do {
            for try await delta in service.stream(prompt: prompt, systemPrompt: nil) {
                deltas += 1
                text += delta
            }
        } catch {
            print("    generation FAILED: \(error.localizedDescription)")
            return
        }

        let elapsed = Date().timeIntervalSince(started)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("    generation produced NO TEXT (\(deltas) delta(s))")
        } else {
            print(String(
                format: "    generated in %.2fs, %d delta(s): \"%@\"",
                elapsed,
                deltas,
                trimmed.prefix(120) as CVarArg
            ))
        }
    }
}
