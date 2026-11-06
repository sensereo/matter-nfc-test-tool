import CryptoKit
import Foundation
@preconcurrency import Matter
import Security

/// A single, atomically replaced Keychain item keeps the signer, IPK and SDK state together.
/// Only used by full commissioning, never by the ephemeral PASE probe.
final class CommissioningStore: NSObject, MTRStorage {
    enum Failure: Error { case keychain(OSStatus), corrupt, writeFailed }
    private let lock = NSLock()
    private var values: [String: Data]
    private var failed = false
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "MatterNFCTestTool.ExperimentalFabric.v1",
        kSecAttrAccount as String: "single-fabric"
    ]

    override init() {
        fatalError("Use init(openExisting:)")
    }

    init(openExisting: Bool) throws {
        var query = Self.query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            guard !openExisting else { throw Failure.corrupt }
            var ipk = Data(count: 16)
            let random = ipk.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            guard random == errSecSuccess else { throw Failure.keychain(random) }
            values = ["app.signer": P256.Signing.PrivateKey().rawRepresentation, "app.ipk": ipk]
        } else {
            guard status == errSecSuccess else { throw Failure.keychain(status) }
            guard let data = result as? Data,
                  let decoded = try? PropertyListDecoder().decode([String: Data].self, from: data),
                  decoded["app.signer"]?.count == 32, decoded["app.ipk"]?.count == 16 else { throw Failure.corrupt }
            values = decoded
        }
        super.init()
        if status == errSecItemNotFound { try save(values) }
    }

    var hasWriteFailure: Bool { lock.lock(); defer { lock.unlock() }; return failed }
    func storageData(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    func setStorageData(_ value: Data, forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var next = values
        next[key] = value
        do { try save(next); values = next; return true }
        catch { failed = true; return false }
    }
    func removeStorageData(forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var next = values
        next.removeValue(forKey: key)
        do { try save(next); values = next; return true }
        catch { failed = true; return false }
    }
    func put(_ value: String, key: String) throws {
        guard setStorageData(Data(value.utf8), forKey: "app." + key) else { throw Failure.writeFailed }
    }
    func text(_ key: String) -> String? {
        storageData(forKey: "app." + key).flatMap { String(data: $0, encoding: .utf8) }
    }
    func clearCurrent() throws {
        try updateMetadata([:], removing: ["currentNode", "expectedPID", "stage", "commissioningBoundary"])
    }
    func reserve(node: UInt64, productID: UInt16) throws {
        try updateMetadata(["nextNode": String(node + 1), "currentNode": String(node),
                            "expectedPID": String(productID), "stage": "establishingNFC",
                            "commissioningBoundary": "notStarted"], removing: [])
    }
    private func updateMetadata(_ additions: [String: String], removing: [String]) throws {
        lock.lock(); defer { lock.unlock() }
        guard !failed else { throw Failure.writeFailed }
        var next = values
        for key in removing { next.removeValue(forKey: "app." + key) }
        for (key, value) in additions { next["app." + key] = Data(value.utf8) }
        do { try save(next); values = next }
        catch { failed = true; throw error }
    }
    private func save(_ next: [String: Data]) throws {
        let data = try PropertyListEncoder().encode(next)
        let status = SecItemUpdate(Self.query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = Self.query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure.keychain(added) }
        } else if status != errSecSuccess { throw Failure.keychain(status) }
    }
}

final class FabricSigningKey: NSObject, MTRKeypair {
    private let key: P256.Signing.PrivateKey
    private let publicKey: SecKey
    init(raw: Data) throws {
        key = try P256.Signing.PrivateKey(rawRepresentation: raw)
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let converted = SecKeyCreateWithData(key.publicKey.x963Representation as CFData, attributes as CFDictionary, nil) else {
            throw CommissioningStore.Failure.corrupt
        }
        publicKey = converted
        super.init()
    }
    func copyPublicKey() -> SecKey { publicKey }
    func signMessageECDSA_DER(_ message: Data) -> Data {
        (try? key.signature(for: message).derRepresentation) ?? Data()
    }
}
