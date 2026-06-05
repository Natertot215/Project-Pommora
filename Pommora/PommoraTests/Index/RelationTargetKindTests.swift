import Testing

@testable import Pommora

/// Verifies the single-source `relations.target_kind` string shared by
/// `IndexBuilder` and `IndexUpdater`. Tier-only post-Relations-redesign;
/// `nil` → "unknown".
@Suite("RelationTargetKindTests")
struct RelationTargetKindTests {

    @Test func contextTierOneMapsToSpace() {
        #expect(RelationTargetKind.string(from: .contextTier(1)) == "space")
    }

    @Test func contextTierTwoMapsToTopic() {
        #expect(RelationTargetKind.string(from: .contextTier(2)) == "topic")
    }

    @Test func contextTierThreeMapsToProject() {
        #expect(RelationTargetKind.string(from: .contextTier(3)) == "project")
    }

    @Test func contextTierUnknownMapsToContext() {
        #expect(RelationTargetKind.string(from: .contextTier(99)) == "context")
    }

    @Test func nilMapsToUnknown() {
        #expect(RelationTargetKind.string(from: nil) == "unknown")
    }
}
