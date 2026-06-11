import Foundation

/// Placeholder for composed-blocks tree entries used by Areas / Topics /
/// Projects / Homepage. The composed-blocks editor lands in v0.9 — until
/// then, this empty struct lets the `blocks: [ContextBlock]` arrays serialize
/// as `[]` and the on-disk schema stays stable.
struct ContextBlock: Codable, Equatable, Hashable, Sendable {
    // intentionally empty in v0.2
}
