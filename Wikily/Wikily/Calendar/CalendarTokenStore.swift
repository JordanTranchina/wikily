import Foundation
import Security

/// One account's OAuth tokens, as far as syncing and refreshing need them.
struct CalendarOAuthTokens: Sendable, Equatable, Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum CalendarTokenStoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case malformedData

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        case .malformedData:
            "Stored calendar credentials could not be read."
        }
    }
}

/// Where calendar OAuth tokens live: the system Keychain, never `UserDefaults`.
///
/// `AppSettings` persists everything else in `UserDefaults` deliberately — see
/// its header comment — but a refresh token is a standing credential to the
/// user's calendar, and a non-sandboxed app's flat, shared defaults domain is
/// exactly the kind of place that shouldn't hold one. The Keychain is the one
/// thing on macOS actually built for this.
protocol CalendarTokenStoring: Sendable {
    func save(_ tokens: CalendarOAuthTokens, for accountID: UUID) throws
    func load(for accountID: UUID) throws -> CalendarOAuthTokens?
    func delete(for accountID: UUID) throws
}

/// The real store, backed by `kSecClassGenericPassword`.
///
/// One item per connected account, keyed by the account's own `UUID` so a
/// disconnect-then-reconnect of the same email never resurrects a stale token
/// under the old account id.
struct KeychainCalendarTokenStore: CalendarTokenStoring {
    private let service = "com.wikily.Wikily.calendar"

    func save(_ tokens: CalendarOAuthTokens, for accountID: UUID) throws {
        let data = try JSONEncoder().encode(tokens)
        var query = baseQuery(for: accountID)

        // Delete-then-add rather than `SecItemUpdate`: simpler to reason
        // about, and this runs at most once per token refresh — not a hot
        // enough path to be worth the extra branch.
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CalendarTokenStoreError.keychain(status) }
    }

    func load(for accountID: UUID) throws -> CalendarOAuthTokens? {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CalendarTokenStoreError.keychain(status) }
        guard let data = result as? Data else { throw CalendarTokenStoreError.malformedData }
        return try JSONDecoder().decode(CalendarOAuthTokens.self, from: data)
    }

    func delete(for accountID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CalendarTokenStoreError.keychain(status)
        }
    }

    private func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }
}

/// In-memory store for tests and SwiftUI previews — never touches the real
/// Keychain, so a test suite that connects and disconnects fake accounts
/// leaves nothing behind on the machine it runs on.
final class InMemoryCalendarTokenStore: CalendarTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: CalendarOAuthTokens] = [:]

    func save(_ tokens: CalendarOAuthTokens, for accountID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        storage[accountID] = tokens
    }

    func load(for accountID: UUID) throws -> CalendarOAuthTokens? {
        lock.lock(); defer { lock.unlock() }
        return storage[accountID]
    }

    func delete(for accountID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: accountID)
    }
}
