import Foundation

/// Deterministic, dependency-free hashes.
///
/// Swift's standard `Hasher` is **randomly seeded per process**, so it cannot be
/// used for either of these: the file fingerprint has to survive an app restart
/// for the incremental re-scan cache to ever hit, and the transcript fingerprint
/// has to be comparable across sessions. Both use FNV-1a, which is stable
/// forever. Neither is cryptographic — collision resistance is not a requirement,
/// only stability and cheapness.
///
/// (The Rust original in `src-tauri/src/wiki.rs` used `DefaultHasher`, which
/// *is* deterministic in Rust — SipHash with fixed keys. Swift has no equivalent
/// guarantee, hence FNV-1a.)
enum StableHash {
    /// 32-bit FNV-1a over UTF-16 code units, as an 8-character hex string.
    ///
    /// Exact port of `stableHash` in `src/lib/wiki/hash.ts` — UTF-16 rather than
    /// UTF-8 so it produces byte-identical output to the TypeScript engine for
    /// the same input, which lets the ported tests assert against known values.
    static func string(_ text: String) -> String {
        var h: UInt32 = 0x811c_9dc5
        for unit in text.utf16 {
            h ^= UInt32(unit)
            // 32-bit FNV prime multiply, wrapping — equivalent to JS `Math.imul`.
            h = h &* 0x0100_0193
        }
        return String(format: "%08x", h)
    }

    /// 64-bit FNV-1a over UTF-8 bytes, as a 16-character hex string.
    ///
    /// Used for file-content fingerprints, where the wider hash meaningfully
    /// lowers the chance of a changed file being mistaken for an unchanged one
    /// and silently serving a stale cache entry.
    static func content(_ text: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", h)
    }
}
