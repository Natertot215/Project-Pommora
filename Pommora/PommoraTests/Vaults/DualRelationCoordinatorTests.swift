import Foundation
import Testing

@testable import Pommora

/// G.4: Tests for `DualRelationCoordinator` — paired-relation lifecycle.
///
/// All tests operate on a temp nexus (filesystem real writes) to exercise the
/// full SchemaTransaction commit path.
@Suite("DualRelationCoordinator")
struct DualRelationCoordinatorTests {

    // MARK: - Helpers

    /// Creates a PageType on disk and returns it.
    @discardableResult
    private static func makePageType(
        id: String = ULID.generate(),
        title: String,
        nexus: Nexus
    ) throws -> PageType {
        let pt = PageType(
            id: id,
            title: title,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let folder = NexusPaths.vaultFolderURL(forTitle: title, in: nexus)
        let meta = NexusPaths.vaultMetadataURL(forTitle: title, in: nexus)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: pt)
        return pt
    }

    /// Creates an ItemType on disk and returns it.
    @discardableResult
    private static func makeItemType(
        id: String = ULID.generate(),
        title: String,
        nexus: Nexus
    ) throws -> ItemType {
        let it = ItemType(
            id: id,
            title: title,
            icon: nil,
            properties: [],
            views: [],
            modifiedAt: Date()
        )
        let folder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: title)
        let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: title)
        try Filesystem.createFolderWithMetadata(folderURL: folder, metadataURL: meta, metadata: it)
        return it
    }

    /// Reloads a PageType from its sidecar.
    private static func reloadPageType(_ title: String, nexus: Nexus) throws -> PageType {
        let meta = NexusPaths.vaultMetadataURL(forTitle: title, in: nexus)
        return try PageType.load(from: meta)
    }

    /// Reloads an ItemType from its sidecar.
    private static func reloadItemType(_ title: String, nexus: Nexus) throws -> ItemType {
        let meta = NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: title)
        return try ItemType.load(from: meta)
    }

    // MARK: - G.4.1: createPairedRelation writes both sides

    @Test("createPairedRelationWritesBothSides — both sidecars updated atomically, IDs cross-reference")
    func createPairedRelationWritesBothSides() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let projectType = try Self.makePageType(title: "Projects", nexus: nexus)
        let taskType = try Self.makeItemType(title: "Tasks", nexus: nexus)

        let (sourceID, targetID) = try DualRelationCoordinator.createPairedRelation(
            source: .pageType(projectType),
            sourcePropertyName: "Tasks",
            sourceScope: .itemType(taskType.id),
            target: .itemType(taskType),
            targetPropertyName: "Projects",
            targetScope: .pageType(projectType.id),
            nexus: nexus
        )

        // Reload both sidecars from disk.
        let reloadedProject = try Self.reloadPageType("Projects", nexus: nexus)
        let reloadedTask = try Self.reloadItemType("Tasks", nexus: nexus)

        // Source side: property added with correct ID.
        let sourceProp = reloadedProject.properties.first { $0.id == sourceID }
        #expect(sourceProp != nil)
        #expect(sourceProp?.name == "Tasks")
        #expect(sourceProp?.type == .relation)
        #expect(sourceProp?.dualProperty?.syncedPropertyID == targetID)
        #expect(sourceProp?.dualProperty?.syncedPropertyDefinedOnTypeID == taskType.id)

        // Target side: reverse property added with correct ID.
        let targetProp = reloadedTask.properties.first { $0.id == targetID }
        #expect(targetProp != nil)
        #expect(targetProp?.name == "Projects")
        #expect(targetProp?.type == .relation)
        #expect(targetProp?.dualProperty?.syncedPropertyID == sourceID)
        #expect(targetProp?.dualProperty?.syncedPropertyDefinedOnTypeID == projectType.id)
    }

    // MARK: - G.4.2: context-tier scope rejected

    @Test("contextTierScopeRejected — coordinator throws for contextTier source scope")
    func contextTierScopeRejectedSource() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pt1 = try Self.makePageType(title: "Notes", nexus: nexus)
        let pt2 = try Self.makePageType(title: "Projects", nexus: nexus)

        #expect(throws: DualRelationCoordinatorError.contextTierScopeRejected) {
            try DualRelationCoordinator.createPairedRelation(
                source: .pageType(pt1),
                sourcePropertyName: "Tier",
                sourceScope: .contextTier(1),   // invalid for dual
                target: .pageType(pt2),
                targetPropertyName: "Notes",
                targetScope: .pageType(pt1.id),
                nexus: nexus
            )
        }
    }

    @Test("contextTierScopeRejected — coordinator throws for contextTier target scope")
    func contextTierScopeRejectedTarget() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let pt1 = try Self.makePageType(title: "Notes", nexus: nexus)
        let pt2 = try Self.makePageType(title: "Projects", nexus: nexus)

        #expect(throws: DualRelationCoordinatorError.contextTierScopeRejected) {
            try DualRelationCoordinator.createPairedRelation(
                source: .pageType(pt1),
                sourcePropertyName: "Projects",
                sourceScope: .pageType(pt2.id),
                target: .pageType(pt2),
                targetPropertyName: "Tier",
                targetScope: .contextTier(2),   // invalid for dual
                nexus: nexus
            )
        }
    }

    // MARK: - G.4.3: renameOneSide does not rewrite member files

    @Test("renameOneSideDoesNotRewriteMemberFiles — only sidecar updated; member files untouched")
    func renameOneSideDoesNotRewriteMemberFiles() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let projectType = try Self.makePageType(title: "Projects", nexus: nexus)
        let taskType = try Self.makeItemType(title: "Tasks", nexus: nexus)

        let (sourceID, _) = try DualRelationCoordinator.createPairedRelation(
            source: .pageType(projectType),
            sourcePropertyName: "Tasks",
            sourceScope: .itemType(taskType.id),
            target: .itemType(taskType),
            targetPropertyName: "Projects",
            targetScope: .pageType(projectType.id),
            nexus: nexus
        )

        // Write a Page file referencing the source property by ID.
        let pageFolder = NexusPaths.vaultFolderURL(forTitle: "Projects", in: nexus)
        let pageFile = pageFolder.appendingPathComponent("Proj-A.md")
        let fm = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [sourceID: .relation("task-01")],
            createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(frontmatter: fm, body: "body\n", to: pageFile)

        let dataBefore = try Data(contentsOf: pageFile)

        // Reload source (needed to have updated dualProperty config).
        let updatedProject = try Self.reloadPageType("Projects", nexus: nexus)

        // Rename the source property.
        try DualRelationCoordinator.renameOneSide(
            propertyID: sourceID,
            in: .pageType(updatedProject),
            to: "My Tasks",
            nexus: nexus
        )

        // Member file must be byte-identical.
        let dataAfter = try Data(contentsOf: pageFile)
        #expect(dataBefore == dataAfter)

        // Sidecar must have new name.
        let reloaded = try Self.reloadPageType("Projects", nexus: nexus)
        let renamed = reloaded.properties.first { $0.id == sourceID }
        #expect(renamed?.name == "My Tasks")
    }

    // MARK: - G.4.4: deletePair cascades values

    @Test("deletePairCascadesValues — both sides removed and member values stripped")
    func deletePairCascadesValues() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let projectType = try Self.makePageType(title: "Projects", nexus: nexus)
        let taskType = try Self.makeItemType(title: "Tasks", nexus: nexus)

        let (sourceID, targetID) = try DualRelationCoordinator.createPairedRelation(
            source: .pageType(projectType),
            sourcePropertyName: "Tasks",
            sourceScope: .itemType(taskType.id),
            target: .itemType(taskType),
            targetPropertyName: "Projects",
            targetScope: .pageType(projectType.id),
            nexus: nexus
        )

        // Write a Page and an Item carrying relation values.
        let pageFolder = NexusPaths.vaultFolderURL(forTitle: "Projects", in: nexus)
        let pageFile = pageFolder.appendingPathComponent("Proj-A.md")
        let pageFM = PageFrontmatter(
            id: ULID.generate(), icon: nil,
            tier1: [], tier2: [], tier3: [],
            properties: [sourceID: .relation("task-01")],
            createdAt: Date()
        )
        try AtomicYAMLMarkdown.write(frontmatter: pageFM, body: "body\n", to: pageFile)

        let itemFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Tasks")
        let itemFile = itemFolder.appendingPathComponent("task-01.json")
        let now = Date()
        let item = Item(
            id: "task-01", title: "task-01", icon: nil, description: "",
            tier1: [], tier2: [], tier3: [],
            properties: [targetID: .relation("proj-01")],
            createdAt: now, modifiedAt: now
        )
        try AtomicJSON.write(item, to: itemFile)

        // Reload updated types (they now have the paired properties).
        let updatedProject = try Self.reloadPageType("Projects", nexus: nexus)
        let updatedTask = try Self.reloadItemType("Tasks", nexus: nexus)

        // Delete the pair.
        try DualRelationCoordinator.deletePair(
            propertyID: sourceID,
            owner: .pageType(updatedProject),
            reverse: .itemType(updatedTask),
            nexus: nexus
        )

        // Both sidecars: properties removed.
        let reloadedProject = try Self.reloadPageType("Projects", nexus: nexus)
        let reloadedTask = try Self.reloadItemType("Tasks", nexus: nexus)
        #expect(reloadedProject.properties.contains { $0.id == sourceID } == false)
        #expect(reloadedTask.properties.contains { $0.id == targetID } == false)

        // Member files: values stripped.
        let (reloadedPageFM, _) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageFile)
        #expect(reloadedPageFM.properties[sourceID] == nil)

        let reloadedItem = try AtomicJSON.decode(Item.self, from: itemFile)
        #expect(reloadedItem.properties[targetID] == nil)
    }

    // MARK: - G.4.5: rollback on partial failure

    @Test("rollbackOnPartialFailure — unwritable target leaves source sidecar unmodified")
    func rollbackOnPartialFailure() throws {
        let nexus = try TempNexus.make()
        defer { TempNexus.cleanup(nexus) }

        let projectType = try Self.makePageType(title: "Projects", nexus: nexus)
        let taskType = try Self.makeItemType(title: "Tasks", nexus: nexus)

        // Capture source sidecar bytes before attempting the paired create.
        let sourceMeta = NexusPaths.vaultMetadataURL(forTitle: "Projects", in: nexus)
        let sourceBytesBefore = try Data(contentsOf: sourceMeta)

        // Make the target sidecar directory read-only so the stage write fails.
        let taskFolder = NexusPaths.itemTypeFolderURL(in: nexus.rootURL, typeFolderName: "Tasks")
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o444)],
            ofItemAtPath: taskFolder.path
        )
        defer {
            // Restore permissions so TempNexus.cleanup can remove the tree.
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)],
                ofItemAtPath: taskFolder.path
            )
        }

        // The create should throw because writing the target sidecar fails.
        #expect(throws: (any Error).self) {
            try DualRelationCoordinator.createPairedRelation(
                source: .pageType(projectType),
                sourcePropertyName: "Tasks",
                sourceScope: .itemType(taskType.id),
                target: .itemType(taskType),
                targetPropertyName: "Projects",
                targetScope: .pageType(projectType.id),
                nexus: nexus
            )
        }

        // Restore permissions before reading.
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: taskFolder.path
        )

        // Source sidecar must be byte-identical to what it was before the attempt.
        let sourceBytesAfter = try Data(contentsOf: sourceMeta)
        #expect(sourceBytesBefore == sourceBytesAfter)
    }
}
