import Foundation

enum ZoneCapRule: Equatable, Sendable { case combinedTotal(Int); case perType(Int) }
struct ItemWindowZonePool: Equatable, Sendable { let types: [PropertyType]; let rule: ZoneCapRule }
enum MuteReason: Equatable, Sendable { case notInV1; case capReached }

enum ItemWindowZoneConfig {
    static let pools: [ItemWindowZonePool] = [
        .init(types: [.select, .multiSelect, .number], rule: .combinedTotal(4)),    // Pool A
        .init(types: [.checkbox, .status, .date, .datetime], rule: .perType(1)),    // Pool B (.date retired from creation; kept for legacy-decode defensiveness)
        .init(types: [.url, .file], rule: .combinedTotal(2)),                       // Pool C
    ]
    static let v1Checkable: Set<PropertyType> = [.select, .multiSelect]
    static func pool(for type: PropertyType) -> ItemWindowZonePool? { pools.first { $0.types.contains(type) } }
    static func isAtCap(_ candidate: PropertyType, pinnedTypes: [PropertyType]) -> Bool {
        guard let p = pool(for: candidate) else { return true }
        switch p.rule {
        case .combinedTotal(let n): return pinnedTypes.filter { p.types.contains($0) }.count >= n
        case .perType(let n):       return pinnedTypes.filter { $0 == candidate }.count >= n
        }
    }
    /// Precedence: .notInV1 ALWAYS wins (checked first; cap only matters for checkable types).
    static func muteReason(_ type: PropertyType, pinnedTypes: [PropertyType]) -> MuteReason? {
        if !v1Checkable.contains(type) { return .notInV1 }
        return isAtCap(type, pinnedTypes: pinnedTypes) ? .capReached : nil
    }
}

extension ItemWindowZoneConfig {
    /// Types of currently-pinned properties, resolved via schema, filtered to v1Checkable
    /// (so stale/off-V1 sidecar entries can't poison a count). Shared by the Templates
    /// pane (cap-count/muting) AND the chip-row slice so their counts never diverge.
    static func pinnedTypes(promoted: [PromotedProperty], schema: [PropertyDefinition]) -> [PropertyType] {
        promoted.compactMap { p in schema.first { $0.id == p.id }?.type }
                .filter { v1Checkable.contains($0) }
    }
}
