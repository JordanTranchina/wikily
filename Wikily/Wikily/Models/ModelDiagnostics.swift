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

    static func isRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(argument)
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
