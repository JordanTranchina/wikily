import SwiftUI

/// Settings › Model: the two models Wikily depends on, and their honest state.
///
/// They are unrelated except that both are on-device and both can be missing.
/// The speech model is a hard requirement — without it there is no transcript
/// and therefore no product — so it goes first and says so. The answering model
/// is optional today and gets the second half.
@MainActor
struct ModelSettingsView: View {

    @Bindable var settings: AppSettings

    @State private var state = ModelSettingsState()

    var body: some View {
        SettingsPane {
            Section {
                StatusIndicator(level: state.speech.level, text: state.speech.description)

                if let progress = state.speech.progress {
                    ProgressView(value: progress)
                }

                if state.speech.canInstall {
                    Button(state.speech.installTitle) {
                        state.speech.install()
                    }
                    .disabled(state.speech.isInstalling)
                }
            } header: {
                Text("Speech Recognition")
            } footer: {
                SettingsFootnote(
                    "Downloading this model is the only time Wikily needs the internet. "
                        + "Once it is installed, calls are transcribed entirely on this "
                        + "Mac and no audio ever leaves it."
                )
            }

            Section {
                Picker("Answering model", selection: $settings.qaModel) {
                    Text("Automatic").tag(ModelDescriptor?.none)
                    ForEach(state.pickerOptions(including: settings.qaModel)) { option in
                        Text(option.descriptor.displayName)
                            .tag(ModelDescriptor?.some(option.descriptor))
                    }
                }

                if let selected = state.option(for: settings.qaModel),
                   !selected.availability.isAvailable {
                    StatusIndicator(
                        level: .problem,
                        text: SettingsFormatting.availability(selected.availability)
                    )
                }
            } header: {
                Text("Answers")
            } footer: {
                SettingsFootnote(
                    "\"Automatic\" uses Apple Intelligence when it is available and "
                        + "falls back to a local server. Wiki card summaries come from "
                        + "the pages themselves and never involve a model."
                )
            }

            Section {
                if state.isProbing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for local model servers…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(state.backendStatuses) { status in
                        StatusIndicator(level: status.level, text: status.text)
                    }
                }

                Button("Check Again") {
                    state.refresh()
                }
                .disabled(state.isProbing)
            } header: {
                Text("Backends")
            } footer: {
                SettingsFootnote(
                    "Wikily looks for Ollama, LM Studio and llama.cpp on their usual "
                        + "ports. Start one and check again — nothing needs configuring."
                )
            }
        }
        .task { await state.load() }
    }
}

// MARK: - State

/// The async half of the Model tab.
///
/// Split out of the view because everything on that pane is the result of I/O —
/// an asset-inventory query, three loopback probes, an Apple Intelligence
/// availability check — and none of it belongs in a `body` that SwiftUI may
/// re-evaluate at any time.
@MainActor
@Observable
final class ModelSettingsState {

    struct ModelOption: Identifiable {
        var descriptor: ModelDescriptor
        var availability: ModelAvailability
        var id: String { descriptor.id }
    }

    struct BackendStatus: Identifiable {
        var id: String
        var level: StatusIndicator.Level
        var text: String
    }

    /// Shared with the first-run wizard so both screens describe the same model
    /// the same way.
    let speech = SpeechModelState()

    private(set) var isProbing = false
    private(set) var selectableModels: [ModelOption] = []
    private(set) var backendStatuses: [BackendStatus] = []

    /// Loaded once when the pane appears; `refresh()` is the explicit re-run.
    private var hasLoaded = false

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func refresh() {
        Task { await reload() }
    }

    private func reload() async {
        await speech.refresh()
        await refreshBackends()
    }

    // MARK: - Backends

    private func refreshBackends() async {
        isProbing = true
        defer { isProbing = false }

        let appleAvailability = await AppleFoundationModelService().availability()
        let endpoints = await LocalServerDiscovery.probeAll()

        var options = [ModelOption(
            descriptor: .appleFoundation,
            availability: appleAvailability
        )]
        for endpoint in endpoints {
            options.append(contentsOf: endpoint.descriptors.map {
                ModelOption(descriptor: $0, availability: .available)
            })
        }
        selectableModels = options

        var statuses = [BackendStatus(
            id: "apple",
            level: appleAvailability.isAvailable ? .ok : .warning,
            text: appleAvailability.isAvailable
                ? "Apple Intelligence is ready."
                : SettingsFormatting.availability(appleAvailability)
        )]

        // Every known server gets a row whether or not it answered. A picker that
        // simply omits Ollama when it isn't running reads as "Wikily doesn't
        // support Ollama", and there is nothing on screen to correct that.
        let found = Dictionary(
            endpoints.compactMap { endpoint in endpoint.kind.map { ($0, endpoint) } },
            uniquingKeysWith: { first, _ in first }
        )
        for kind in LocalServerKind.allCases {
            if let endpoint = found[kind] {
                statuses.append(BackendStatus(
                    id: kind.rawValue,
                    level: endpoint.models.isEmpty ? .warning : .ok,
                    text: endpoint.models.isEmpty
                        ? "\(kind.displayName) is running but has no models installed."
                        : "\(kind.displayName): "
                            + SettingsFormatting.count(
                                endpoint.models.count,
                                singular: "model"
                            )
                            + " available."
                ))
            } else {
                statuses.append(BackendStatus(
                    id: kind.rawValue,
                    level: .unknown,
                    text: "\(kind.displayName) isn't running on port \(kind.port)."
                ))
            }
        }
        backendStatuses = statuses
    }

    /// Picker rows, guaranteed to contain the current selection.
    ///
    /// Without the append, a persisted model whose server is down has no row to
    /// match its tag and SwiftUI renders the picker blank — which looks exactly
    /// like "nothing is selected" and invites the user to pick again, quietly
    /// losing a choice that was fine.
    func pickerOptions(including selected: ModelDescriptor?) -> [ModelOption] {
        guard let selected,
              !selectableModels.contains(where: { $0.descriptor.id == selected.id }),
              let missing = option(for: selected)
        else { return selectableModels }
        return selectableModels + [missing]
    }

    /// The option matching a descriptor, including one that is persisted but no
    /// longer discoverable — a server that was running when it was chosen and is
    /// not running now. Reporting it as unavailable is the whole point; dropping
    /// it would silently reset the user's choice.
    func option(for descriptor: ModelDescriptor?) -> ModelOption? {
        guard let descriptor else { return nil }
        if let known = selectableModels.first(where: { $0.descriptor.id == descriptor.id }) {
            return known
        }
        return ModelOption(
            descriptor: descriptor,
            availability: .unavailable(
                reason: "\(descriptor.displayName) isn't reachable right now.",
                recovery: "Start the server, or pick another model."
            )
        )
    }
}
