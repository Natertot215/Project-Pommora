import Foundation
import Testing

@testable import Pommora

/// RED baseline for the manager-level `updatePairedRelation` wrapper
/// (PageTypeManager / ItemTypeManager). The wrapper updates ONLY the reverse
/// (mirror) side of a paired relation — reading the home side's current
/// name/icon and routing both sides through `DualRelationCoordinator.updatePairedRelation`
/// (F3) so the home side is preserved while the reverse is rewritten.
///
/// This suite fails against the no-op stub wrappers: the reverse property keeps
/// its created value instead of taking the new name/icon. The controller fills
/// in the real persistence next, turning this GREEN.
///
/// Operates on a temp nexus (real filesystem writes) and reloads both sidecars
/// from disk to prove the persisted state, mirroring `DualRelationWiringTests` +
/// `PairedRelationUpdateTests`.
@MainActor
@Suite("PairedRelationManagerUpdateTests")
struct PairedRelationManagerUpdateTests {

    @Test("updatePairedRelation rewrites only the reverse side; home name+icon unchanged")
    func updatePairedRelationUpdatesReverseSideOnly() async throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let manager = PageTypeManager(nexus: nexus)
        await manager.loadAll()

        try await manager.createPageType(name: "Books", icon: nil)
        try await manager.createPageType(name: "Authors", icon: nil)

        let books = manager.types.first { $0.title == "Books" }!
        let authors = manager.types.first { $0.title == "Authors" }!

        // Create a paired relation on the source (home: "Authors"/"person" on
        // Books; reverse: "Books"/"book" on Authors). Convention mirrored from
        // DualRelationWiringTests: `reverseName` carries the reverse display name
        // at add-time; `dualProperty` (empty syncedPropertyID) is the pairing signal.
        let def = PropertyDefinition(
            id: "",
            name: "Authors",
            type: .relation,
            icon: "person",
            relationTarget: .pageType(authors.id),
            reverseName: "Books",
            reverseIcon: "book",
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: "",
                syncedPropertyDefinedOnTypeID: authors.id
            )
        )
        try await manager.addProperty(def, to: books.id)

        // The minted home (source) property ID.
        let homeProp = manager.types.first { $0.title == "Books" }!
            .properties.first { $0.type == .relation }!
        let homePropID = homeProp.id

        // Update ONLY the reverse (mirror) side via the new wrapper.
        try await manager.updatePairedRelation(
            propertyID: homePropID,
            newReverseName: "Written by",
            newReverseIcon: "pencil",
            in: books.id
        )

        // Reload BOTH types from disk to read the persisted state.
        let reloadedBooksMeta = NexusPaths.vaultMetadataURL(forTitle: "Books", in: nexus)
        let reloadedAuthorsMeta = NexusPaths.vaultMetadataURL(forTitle: "Authors", in: nexus)
        let reloadedBooks = try PageType.load(from: reloadedBooksMeta)
        let reloadedAuthors = try PageType.load(from: reloadedAuthorsMeta)

        let reloadedHome = reloadedBooks.properties.first { $0.id == homePropID }
        let reloadedReverse = reloadedAuthors.properties.first { $0.type == .relation }

        // Reverse (mirror) side: new name + icon written.
        #expect(reloadedReverse?.name == "Written by")
        #expect(reloadedReverse?.icon == "pencil")

        // Home side: name + icon UNCHANGED (the wrapper touches only the mirror).
        #expect(reloadedHome?.name == "Authors")
        #expect(reloadedHome?.icon == "person")
    }
}
