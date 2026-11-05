import Foundation
import Testing
@testable import PluginSorterCore

/// The stand-in for the Keychain: the real one may stop a test run with a password dialog.
final class InMemoryStore: SecretStore {
    var records: [String: Data] = [:]
    var readCount = 0
    var failWith: Error?

    func accounts() throws -> Set<String> {
        if let failWith = failWith { throw failWith }
        return Set(records.keys)
    }

    func read(_ account: String) throws -> Data? {
        if let failWith = failWith { throw failWith }
        readCount += 1
        return records[account]
    }

    func write(_ data: Data, account: String) throws {
        if let failWith = failWith { throw failWith }
        records[account] = data
    }

    func delete(_ account: String) throws {
        if let failWith = failWith { throw failWith }
        records[account] = nil
    }
}

private struct Boom: Error, Equatable {}

@Suite("Licenses in the Keychain")
struct LicenseVaultTests {
    private let sample = License(serial: "AAAA-BBBB", email: "me@example.com", note: "bought 2024")

    @Test func saveThenReadReturnsTheSame() throws {
        let vault = LicenseVault(store: InMemoryStore())
        try vault.save(sample, for: "serum")
        #expect(try vault.license("serum") == sample)
        #expect(try vault.license("other") == nil)
        #expect(vault.hasLicense("serum"))
    }

    @Test func emptyLicenseRemovesTheRecord() throws {
        let store = InMemoryStore()
        let vault = LicenseVault(store: store)
        try vault.save(sample, for: "serum")
        try vault.save(License(serial: "  ", email: "", note: "\n"), for: "serum")
        #expect(store.records.isEmpty)
        #expect(!vault.hasLicense("serum"))
    }

    @Test func removeDeletesTheRecord() throws {
        let store = InMemoryStore()
        let vault = LicenseVault(store: store)
        try vault.save(sample, for: "serum")
        try vault.remove("serum")
        #expect(store.records.isEmpty)
        #expect(!vault.hasLicense("serum"))
    }

    @Test func hasLicenseDoesNotReadSecrets() throws {
        let store = InMemoryStore()
        let vault = LicenseVault(store: store)
        try vault.save(sample, for: "serum")
        _ = vault.hasLicense("serum")
        _ = vault.hasLicense("other")
        #expect(store.readCount == 0)
    }

    @Test func storeErrorReachesTheCaller() throws {
        let store = InMemoryStore()
        let vault = LicenseVault(store: store)
        store.failWith = Boom()
        #expect(throws: Boom.self) { try vault.save(sample, for: "serum") }
        #expect(throws: Boom.self) { try vault.license("serum") }
        #expect(throws: Boom.self) { try vault.remove("serum") }
        // The failed write left no mark in the "has a license" answer
        store.failWith = nil
        #expect(!vault.hasLicense("serum"))
    }

    @Test func unreadableRecordIsAnErrorNotEmpty() throws {
        let store = InMemoryStore()
        store.records["serum"] = Data("not a license".utf8)
        let vault = LicenseVault(store: store)
        #expect(vault.hasLicense("serum"))
        #expect(throws: SecretStoreError.self) { try vault.license("serum") }
    }

    @Test func answerFollowsLaterChanges() throws {
        let store = InMemoryStore()
        let vault = LicenseVault(store: store)
        #expect(!vault.hasLicense("serum"))                       // the answer is cached from here on
        try vault.save(sample, for: "serum")
        #expect(vault.hasLicense("serum"))
        try vault.remove("serum")
        #expect(!vault.hasLicense("serum"))
    }
}
