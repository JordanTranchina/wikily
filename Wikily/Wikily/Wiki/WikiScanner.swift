import Foundation

/// Recursively reads a user-selected directory of markdown files.
///
/// Port of `src-tauri/src/wiki.rs`. Nothing here ever leaves the machine —
/// contents are read, fingerprinted, and handed to the in-process parser and
/// index (Product Spec §4.2, "100% Local-First").
enum WikiScanner {

    struct ScanResult: Sendable {
        var files: [RawWikiFile]
        /// Directories visited, surfaced as diagnostics in the settings UI.
        var scannedDirectoryCount: Int
    }

    enum ScanError: LocalizedError, Equatable {
        case directoryDoesNotExist(String)
        case notADirectory(String)

        var errorDescription: String? {
            switch self {
            case .directoryDoesNotExist(let path):
                "That folder no longer exists: \(path)"
            case .notADirectory(let path):
                "That path isn't a folder: \(path)"
            }
        }
    }

    /// Per-file size cap. Anything larger is almost certainly not a wiki page,
    /// and reading it would stall indexing for no benefit.
    static let maximumFileBytes = 2 * 1024 * 1024

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdx"]

    /// Directories never descended into: VCS, vault tooling metadata, deps.
    static func isIgnoredDirectory(_ name: String) -> Bool {
        if ["node_modules"].contains(name) { return true }
        // Every dotted directory is skipped, which subsumes .git, .obsidian,
        // .trash, .vscode and .idea from the Rust original.
        return name.hasPrefix(".") && name.count > 1
    }

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func scan(directory path: String) throws -> ScanResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ScanError.directoryDoesNotExist(path)
        }
        guard isDirectory.boolValue else {
            throw ScanError.notADirectory(path)
        }

        var files: [RawWikiFile] = []
        var scannedDirectoryCount = 0
        walk(
            URL(fileURLWithPath: path, isDirectory: true),
            into: &files,
            scannedDirectoryCount: &scannedDirectoryCount
        )

        // Stable order regardless of filesystem enumeration order, so an
        // unchanged vault always produces an identical index.
        files.sort { $0.path < $1.path }
        return ScanResult(files: files, scannedDirectoryCount: scannedDirectoryCount)
    }

    private static func walk(
        _ directory: URL,
        into files: inout [RawWikiFile],
        scannedDirectoryCount: inout Int
    ) {
        scannedDirectoryCount += 1

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            // An unreadable directory is skipped rather than failing the whole
            // scan — one bad permission shouldn't cost the user their index.
            return
        }

        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }

            if values.isDirectory == true {
                guard !isIgnoredDirectory(entry.lastPathComponent) else { continue }
                walk(entry, into: &files, scannedDirectoryCount: &scannedDirectoryCount)
                continue
            }

            guard values.isRegularFile == true, isMarkdown(entry) else { continue }
            if let size = values.fileSize, size > maximumFileBytes { continue }
            guard let content = try? String(contentsOf: entry, encoding: .utf8) else { continue }

            files.append(
                RawWikiFile(
                    path: entry.path,
                    name: entry.deletingPathExtension().lastPathComponent,
                    content: content,
                    hash: StableHash.content(content)
                )
            )
        }
    }
}
