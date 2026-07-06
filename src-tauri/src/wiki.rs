// Wikily: local markdown wiki scanner.
//
// Recursively reads a user-selected directory of markdown files and returns
// their raw contents to the frontend, which parses + indexes them entirely
// on-device. No content ever leaves the machine (spec §4.2 "100% Local-First").

use serde::Serialize;
use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::Path;

#[derive(Serialize)]
pub struct WikiFile {
    /// Absolute path on disk.
    path: String,
    /// File name without extension (used as a fallback title).
    name: String,
    /// Raw markdown contents.
    content: String,
    /// Stable hash of the raw contents, used by the frontend to skip
    /// re-parsing/re-indexing files that have not changed (spec §5.7).
    hash: String,
}

/// Cheap, stable content fingerprint. Only needs to detect change, not resist
/// collisions, so the std hasher is fine and keeps us dependency-free.
fn content_hash(content: &str) -> String {
    let mut hasher = DefaultHasher::new();
    content.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

#[derive(Serialize)]
pub struct WikiScanResult {
    files: Vec<WikiFile>,
    /// Number of directories visited (diagnostics for the settings UI).
    scanned_dirs: usize,
}

const MAX_FILE_BYTES: u64 = 2 * 1024 * 1024; // 2 MB per file safety cap

fn is_markdown(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|e| e.to_str()).map(|e| e.to_lowercase()),
        Some(ref e) if e == "md" || e == "markdown" || e == "mdx"
    )
}

/// Directories we never want to descend into (vault/tooling metadata, VCS, deps).
fn is_ignored_dir(name: &str) -> bool {
    matches!(
        name,
        ".git" | ".obsidian" | ".trash" | "node_modules" | ".vscode" | ".idea"
    ) || name.starts_with('.') && name.len() > 1
}

fn walk(dir: &Path, files: &mut Vec<WikiFile>, scanned_dirs: &mut usize) {
    *scanned_dirs += 1;
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let file_type = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };

        if file_type.is_dir() {
            let dir_name = path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");
            if is_ignored_dir(dir_name) {
                continue;
            }
            walk(&path, files, scanned_dirs);
        } else if file_type.is_file() && is_markdown(&path) {
            // Skip oversized files to keep indexing fast.
            if let Ok(meta) = entry.metadata() {
                if meta.len() > MAX_FILE_BYTES {
                    continue;
                }
            }
            if let Ok(content) = fs::read_to_string(&path) {
                let name = path
                    .file_stem()
                    .and_then(|n| n.to_str())
                    .unwrap_or("untitled")
                    .to_string();
                let hash = content_hash(&content);
                files.push(WikiFile {
                    path: path.to_string_lossy().to_string(),
                    name,
                    content,
                    hash,
                });
            }
        }
    }
}

#[tauri::command]
pub fn scan_wiki_directory(path: String) -> Result<WikiScanResult, String> {
    let root = Path::new(&path);
    if !root.exists() {
        return Err(format!("Directory does not exist: {}", path));
    }
    if !root.is_dir() {
        return Err(format!("Not a directory: {}", path));
    }

    let mut files = Vec::new();
    let mut scanned_dirs = 0usize;
    walk(root, &mut files, &mut scanned_dirs);

    Ok(WikiScanResult {
        files,
        scanned_dirs,
    })
}
