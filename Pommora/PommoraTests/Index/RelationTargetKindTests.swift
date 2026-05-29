import Testing

@testable import Pommora

/// Verifies the single-source `relations.target_kind` mapping shared by
/// `IndexBuilder` and `IndexUpdater`. Container targets collapse to the
/// contained entity's kind; context tiers map by tier number; `nil` → "unknown".
@Suite("RelationTargetKindTests")
struct RelationTargetKindTests {

    @Test func pageTypeMapsToPage() {
        #expect(RelationTargetKind.string(from: .pageType("PT1")) == "page")
    }

    @Test func pageCollectionMapsToPage() {
        #expect(RelationTargetKind.string(from: .pageCollection("PC1")) == "page")
    }

    @Test func itemTypeMapsToItem() {
        #expect(RelationTargetKind.string(from: .itemType("IT1")) == "item")
    }

    @Test func itemCollectionMapsToItem() {
        #expect(RelationTargetKind.string(from: .itemCollection("IC1")) == "item")
    }

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

    @Test func agendaTasksMapsToAgendaTask() {
        #expect(RelationTargetKind.string(from: .agendaTasks) == "agenda_task")
    }

    @Test func agendaEventsMapsToAgendaEvent() {
        #expect(RelationTargetKind.string(from: .agendaEvents) == "agenda_event")
    }

    @Test func nilMapsToUnknown() {
        #expect(RelationTargetKind.string(from: nil) == "unknown")
    }
}
