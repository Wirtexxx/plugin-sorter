import Foundation
import Security

/// What a user keeps about a purchase.
struct License: Codable, Equatable {
    var serial = ""
    var email = ""
    var note = ""

    var isEmpty: Bool {
        [serial, email, note].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum SecretStoreError: Error, Equatable, LocalizedError {
    /// The user closed the Keychain's password dialog: not a failure to report.
    case cancelled
    case status(Int32)
    /// A record is there but is not a license we wrote.
    case unreadable

    var errorDescription: String? {
        switch self {
        case .cancelled:        return nil
        case .unreadable:       return "The saved license can't be read"
        case .status(let code): return (SecCopyErrorMessageString(OSStatus(code), nil) as String?) ?? "Keychain error \(code)"
        }
    }
}

/// Where the secrets are kept, by account. The Keychain in the app, a dictionary in tests.
protocol SecretStore {
    /// The accounts that have a record. Never reads a secret, so it never asks for a password.
    func accounts() throws -> Set<String>
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(_ account: String) throws
}

/// The login Keychain: generic passwords of one service, not synced to iCloud.
struct KeychainStore: SecretStore {
    let service: String

    private func query(_ account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
        if let account = account { query[kSecAttrAccount as String] = account }
        return query
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:      return
        case errSecUserCanceled: throw SecretStoreError.cancelled
        default:                 throw SecretStoreError.status(status)
        }
    }

    func accounts() throws -> Set<String> {
        var query = self.query()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true      // the attributes only: no kSecReturnData, so no password dialog
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        let items = result as? [[String: Any]] ?? []
        return Set(items.compactMap { $0[kSecAttrAccount as String] as? String })
    }

    func read(_ account: String) throws -> Data? {
        var query = self.query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return result as? Data
    }

    func write(_ data: Data, account: String) throws {
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query(account) as CFDictionary, update)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            try check(SecItemAdd(add as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}

/// Plugin licenses by `plugin.key`. Whether a license exists is known without reading it; the text
/// itself is read only when asked for.
final class LicenseVault {
    static let service = "io.github.wirtexxx.plugin-sorter.license"

    private let store: SecretStore
    /// Kept after the first look: the list asks on every redraw. Dropped by every change.
    private var accounts: Set<String>?

    init(store: SecretStore) {
        self.store = store
    }

    func hasLicense(_ key: String) -> Bool {
        if accounts == nil { accounts = try? store.accounts() }
        return accounts?.contains(key) ?? false
    }

    /// Nil when there is no record. A record that isn't a license is an error, not an empty license.
    func license(_ key: String) throws -> License? {
        guard let data = try store.read(key) else { return nil }
        guard let license = try? JSONDecoder().decode(License.self, from: data) else { throw SecretStoreError.unreadable }
        return license
    }

    /// An empty license removes the record.
    func save(_ license: License, for key: String) throws {
        accounts = nil
        if license.isEmpty { return try store.delete(key) }
        try store.write(try JSONEncoder().encode(license), account: key)
    }

    func remove(_ key: String) throws {
        accounts = nil
        try store.delete(key)
    }
}
