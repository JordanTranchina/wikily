import AppKit
import SwiftUI

/// Settings › Knowledge Base: which folder Wikily reads, and what it found in it.
///
/// The stats are the point of this pane. A folder path alone tells the user
/// nothing about whether Wikily can actually do its job — "0 pages" from a vault
/// full of `.txt` files is a diagnosis, and it is not one the user can reach any
/// other way.
@MainActor
struct KnowledgeBaseSettingsView: View {

    @Bindable var settings: AppSettings

    @State private var isScanning = false
    @State private var scanError: String?

    var body: some View {
        SettingsPane {
            Section {
                LabeledContent("Folder") {
                    if let path = settings.wikiFolderPath {
                        Text(displayPath(path))
                            .textSelection(.enabled)
                            .truncationMode(.head)
                            .lineLimit(1)
                            .help(path)
                    } else {
                        Text("None chosen")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(settings.wikiFolderPath == nil ? "Choose Folder…" : "Change Folder…") {
                        chooseFolder()
                    }
                    Button("Re-scan") {
                        rescan()
                    }
                    .disabled(settings.wikiFolderPath == nil || isScanning)

                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 4)
                    }
                }
            } header: {
                Text("Wiki Folder")
            } footer: {
                SettingsFootnote(
                    "Wikily reads Markdown files (.md, .markdown, .mdx) from this "
                        + "folder and everything inside it, skipping hidden folders and "
                        + "node_modules. Files are read and indexed on this Mac; nothing "
                        + "is uploaded."
                )
            }

            Section("Index") {
                if let error = scanError {
                    StatusIndicator(level: .problem, text: error)
                }

                if let stats = settings.indexStats {
                    LabeledContent(
                        "Pages",
                        value: SettingsFormatting.count(stats.documentCount, singular: "page")
                    )
                    LabeledContent(
                        "Vocabulary",
                        value: SettingsFormatting.count(stats.tokenCount, singular: "term")
                    )
                    LabeledContent(
                        "Last indexed",
                        value: SettingsFormatting.lastIndexed(stats.indexedAt)
                    )

                    if stats.documentCount == 0 {
                        StatusIndicator(
                            level: .warning,
                            text: "No Markdown pages were found in that folder, so Wikily "
                                + "has nothing to suggest during a call."
                        )
                    }
                } else {
                    StatusIndicator(
                        level: .unknown,
                        text: settings.wikiFolderPath == nil
                            ? "Choose a folder to build the index."
                            : "Not indexed yet. Re-scan to build the index."
                    )
                }
            }

            Section {
                Button("Clear Cached Pages") {
                    WikiIndexCache().clear()
                }
            } footer: {
                SettingsFootnote(
                    "Wikily keeps parsed pages on disk so a re-scan only re-reads what "
                        + "changed. Clearing that cache forces the next scan to parse "
                        + "everything from scratch — worth trying if a page looks stale."
                )
            }
        }
    }

    /// Abbreviates the home directory, because a settings row is not wide enough
    /// for `/Users/somebody/Documents/…` and the prefix is the least informative
    /// part of the path.
    private func displayPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder holding your Markdown wiki."
        if let current = settings.wikiFolderPath {
            panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try await settings.setWikiFolder(url.path) }
    }

    private func rescan() {
        run { try await settings.rescanWiki() }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        isScanning = true
        scanError = nil
        Task {
            do {
                try await work()
            } catch {
                scanError = error.localizedDescription
            }
            isScanning = false
        }
    }
}
