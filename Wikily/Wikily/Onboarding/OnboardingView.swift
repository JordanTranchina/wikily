import AppKit
import SwiftUI

/// The first-run wizard.
///
/// The governing decision is that **no step is a wall**. Both real steps can be
/// skipped: a user with no wiki yet, or on a metered connection, gets into the
/// app and finds the same controls in Settings later. A first-run flow that
/// traps someone behind a download is how an app gets force-quit and never
/// reopened, and neither of these choices is irreversible.
///
/// The speech-model step is nonetheless explicit that skipping it leaves
/// transcription broken, because the alternative — a cheerful "Later" button and
/// a silent app afterwards — is worse than an honest warning.
@MainActor
struct OnboardingView: View {

    @Bindable var settings: AppSettings

    /// Invoked when the wizard is finished or dismissed. The caller closes the
    /// window; this view does not know it is in one.
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .wikiFolder
    @State private var speech = SpeechModelState()
    @State private var isScanning = false
    @State private var scanError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            Group {
                switch step {
                case .wikiFolder: wikiFolderStep
                case .speechModel: speechModelStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)

            Divider()
            footer
        }
        .frame(width: 520, height: 380)
        .task { await speech.refresh() }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(step.position) of \(OnboardingStep.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(step.title)
                .font(.title2.weight(.semibold))
            Text(step.subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private var footer: some View {
        HStack {
            if let previous = step.previous {
                Button("Back") { step = previous }
            }
            Spacer()
            secondaryAction
            primaryAction
        }
        .padding(16)
    }

    @ViewBuilder
    private var secondaryAction: some View {
        switch step {
        case .wikiFolder:
            Button("Skip for now") { advance() }
        case .speechModel:
            Button("Skip for now") { advance() }
                .disabled(speech.isInstalling)
        case .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch step {
        case .wikiFolder:
            Button("Continue") { advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(settings.wikiFolderPath == nil || isScanning)
        case .speechModel:
            Button("Continue") { advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(speech.isInstalling)
        case .done:
            Button("Start Using Wikily") { finish() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Steps

    private var wikiFolderStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Choose Folder…") { chooseFolder() }
                .controlSize(.large)

            if isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your wiki…").foregroundStyle(.secondary)
                }
            }

            if let scanError {
                StatusIndicator(level: .problem, text: scanError)
            } else if let path = settings.wikiFolderPath {
                StatusIndicator(
                    level: .ok,
                    text: (path as NSString).abbreviatingWithTildeInPath
                )
                if let stats = settings.indexStats {
                    StatusIndicator(
                        level: stats.documentCount == 0 ? .warning : .ok,
                        text: stats.documentCount == 0
                            ? "No Markdown pages in that folder — try another one."
                            : "Found "
                                + SettingsFormatting.count(stats.documentCount, singular: "page")
                                + "."
                    )
                }
            }

            Spacer()
            SettingsFootnote(
                "You can change this later in Settings, and Wikily re-reads the folder "
                    + "whenever you ask it to."
            )
        }
    }

    private var speechModelStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusIndicator(level: speech.level, text: speech.description)

            if let progress = speech.progress {
                ProgressView(value: progress)
            }

            if speech.canInstall {
                Button(speech.installTitle) { speech.install() }
                    .controlSize(.large)
                    .disabled(speech.isInstalling)
            }

            Spacer()

            if !speech.isReady {
                SettingsFootnote(
                    "Skipping is fine — Wikily will still start, show the menu bar item "
                        + "and index your wiki. It just won't hear anything until this "
                        + "model is installed, which you can do any time from "
                        + "Settings › Model."
                )
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Wikily is in your menu bar — look for the waveform icon.",
                systemImage: "waveform.circle"
            )
            Label(
                "Start listening from that menu when a call begins.",
                systemImage: "play.circle"
            )
            Label(
                "Everything stays on this Mac: no account, no uploads.",
                systemImage: "lock"
            )

            if settings.wikiFolderPath != nil {
                Label(
                    "Indexing continues in the background; you don't have to wait.",
                    systemImage: "clock.arrow.circlepath"
                )
            }

            Spacer()
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: - Actions

    private func advance() {
        guard let next = step.next else { return finish() }
        step = next
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder holding your Markdown wiki."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isScanning = true
        scanError = nil
        Task {
            do {
                try await settings.setWikiFolder(url.path)
            } catch {
                scanError = error.localizedDescription
            }
            isScanning = false
        }
    }
}
