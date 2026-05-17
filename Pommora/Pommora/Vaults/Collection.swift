import Foundation
import CryptoKit

/// In-app value type for a Collection (Vault sub-folder).
/// Not serialised — collections have no `_collection.json` in v1.
/// Identity is the SHA-256 of the folder URL path (stable across runs).
struct Collection: Equatable, Identifiable, Hashable, Sendable {
    let id: String
    let vaultID: String
    let title: String
    let folderURL: URL

    init(folderURL: URL, vaultID: String) {
        self.folderURL = folderURL
        self.vaultID = vaultID
        self.title = folderURL.lastPathComponent
        // SHA-256 of normalized path → 64-char hex; deterministic across runs
        let normalized = folderURL.standardizedFileURL.path
        let hash = SHA256.hash(data: Data(normalized.utf8))
        self.id = hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
