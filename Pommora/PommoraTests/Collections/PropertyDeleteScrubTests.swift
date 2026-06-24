import Foundation
import Testing

@testable import Pommora

/// Regression guard for the property-delete SavedView scrub (Issue A).
///
/// When a schema property is deleted, existing SavedViews that reference it by
/// id keep dangling references. The pipeline resolvers no-op, but a view
/// `group`ed by the deleted property collapses every page into one "No Value"
/// bucket, and a view `sort`ed by it silently un-sorts with an invisible
/// criterion. The fix scrubs the deleted id from every view of the container.
///
/// The fixture hits real disk (mirrors `UpdateViewClobberTests` /
/// `PageCollectionManagerSchemaCRUDTests`) and asserts on the sidecar read FRESH from
/// disk so the scrub is verified at the persistence layer.
@MainActor
@Suite("PropertyDeleteScrubTests")
struct PropertyDeleteScrubTests {

    @Test("deleteProperty scrubs the id from group, sort, order, hidden, and widths on every view")
    func deletePropertyScrubsAllViews() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = PageCollectionManager(nexus: nexus)
        await manager.loadAll()
        try await manager.createPageCollection(name: "Notes", icon: nil)
        let collectionID = manager.types.first!.id

        // Add the property we'll later delete.
        try await manager.addProperty(
            PropertyDefinition(id: "", name: "Priority", type: .number), to: collectionID)
        let propID = manager.types.first { $0.id == collectionID }!.properties[0].id

        // Add a view and configure it to reference the property in EVERY place
        // the scrub must touch: group, sort, propertyOrder, hiddenProperties,
        // columnWidths. `collapsedGroups` carries a non-property group key that
        // must survive untouched.
        let view = try await manager.addView(type: .table, to: collectionID)
        try await manager.updateView(view.id, in: collectionID) { v in
            v.group = .property(PropertyGrouping(propertyID: propID, order: nil))
            v.sort = [
                SortCriterion(propertyID: propID, direction: .ascending),
                SortCriterion(propertyID: ReservedPropertyID.modifiedAt, direction: .descending),
            ]
            v.propertyOrder = [ReservedPropertyID.title, propID]
            v.hiddenProperties = [propID]
            v.columnWidths = [propID: 180, ReservedPropertyID.title: 200]
            v.collapsedGroups = ["High"]
        }

        // Delete the property — the scrub runs as part of this call.
        try await manager.deleteProperty(id: propID, in: collectionID)

        // Assert on the sidecar read FRESH from disk.
        let meta = NexusPaths.collectionMetadataURL(forTitle: "Notes", in: nexus)
        let reloaded = try PageCollection.load(from: meta)
        let scrubbed = try #require(reloaded.views.first { $0.id == view.id })

        // group reset to structural.
        #expect(scrubbed.group == .structural)
        // sort criterion for the deleted property dropped; the other survives.
        #expect(scrubbed.sort == [SortCriterion(propertyID: ReservedPropertyID.modifiedAt, direction: .descending)])
        // order + hidden scrubbed (title survives).
        #expect(scrubbed.propertyOrder == [ReservedPropertyID.title])
        #expect(scrubbed.hiddenProperties == [])
        // column width entry dropped (title width survives).
        #expect(scrubbed.columnWidths == [ReservedPropertyID.title: 200])
        // group keys (collapsedGroups) are NOT property ids — left intact.
        #expect(scrubbed.collapsedGroups == ["High"])
    }
}
