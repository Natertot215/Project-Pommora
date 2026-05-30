import Foundation

/// Errors thrown by `DualRelationCoordinator`.
enum DualRelationCoordinatorError: Error, Equatable {
    /// Caller tried to create a paired relation with a `contextTier` scope.
    /// Context-tier relations are query-derived; they cannot have a sidecar-level reverse.
    case contextTierScopeRejected
    /// Source Type not found in the nexus (PageType or ItemType).
    case sourceTypeNotFound
    /// Target Type not found in the nexus.
    case targetTypeNotFound
    /// The property carrying a `dualProperty` config was not found.
    case propertyNotFound
    /// The named reverse property on the paired Type was not found.
    case reversePropertyNotFound
}

/// Manages paired-relation lifecycle for `PropertyDefinition`s that carry a
/// `dualProperty` config. Both sides of the pair are kept in sync atomically
/// via `SchemaTransaction`.
///
/// - Source and target can each be a PageType or an ItemType — the coordinator
///   discovers the sidecar URL from the nexus root by title.
/// - ContextTier relation scopes are always rejected (validator rule 6).
///
/// **Usage contract**: callers supply resolved `PageType` / `ItemType` values
/// from their respective managers so the coordinator never has to discover them
/// itself; the coordinaor only touches sidecars on disk.
struct DualRelationCoordinator: Sendable {

    // MARK: - Typed scope discriminator

    /// Which kind of container owns a sidecar that the coordinator can write.
    enum TypeKind: Sendable {
        case pageType(PageType)
        case itemType(ItemType)
        case agendaTasks(AgendaTaskSchema)
        case agendaEvents(AgendaEventSchema)
    }

    // MARK: - Private helpers

    /// Returns the on-disk URL for a Type's sidecar given its `TypeKind`.
    private static func sidecarURL(for kind: TypeKind, nexus: Nexus) -> URL {
        switch kind {
        case .pageType(let pt):
            return NexusPaths.vaultMetadataURL(forTitle: pt.title, in: nexus)
        case .itemType(let it):
            return NexusPaths.itemTypeMetadataURL(in: nexus.rootURL, typeFolderName: it.title)
        case .agendaTasks:
            return NexusPaths.taskSchemaURL(in: nexus)
        case .agendaEvents:
            return NexusPaths.eventSchemaURL(in: nexus)
        }
    }

    /// Returns the current `properties` array from a `TypeKind`.
    private static func properties(of kind: TypeKind) -> [PropertyDefinition] {
        switch kind {
        case .pageType(let pt): return pt.properties
        case .itemType(let it): return it.properties
        case .agendaTasks(let s): return s.properties
        case .agendaEvents(let s): return s.properties
        }
    }

    /// Returns a new `TypeKind` with the given `properties` substituted in.
    private static func replacing(properties: [PropertyDefinition], in kind: TypeKind) -> TypeKind {
        switch kind {
        case .pageType(var pt):
            pt.properties = properties
            pt.modifiedAt = Date()
            return .pageType(pt)
        case .itemType(var it):
            it.properties = properties
            it.modifiedAt = Date()
            return .itemType(it)
        case .agendaTasks(var s):
            s.properties = properties
            s.modifiedAt = Date()
            return .agendaTasks(s)
        case .agendaEvents(var s):
            s.properties = properties
            s.modifiedAt = Date()
            return .agendaEvents(s)
        }
    }

    /// Stages a `TypeKind`'s sidecar into a `SchemaTransaction`.
    private static func stage(_ kind: TypeKind, to tx: SchemaTransaction, nexus: Nexus) throws {
        let url = sidecarURL(for: kind, nexus: nexus)
        switch kind {
        case .pageType(let pt):
            try tx.stage(pt, to: url)
        case .itemType(let it):
            try tx.stage(it, to: url)
        case .agendaTasks(let s):
            try tx.stage(s, to: url)
        case .agendaEvents(let s):
            try tx.stage(s, to: url)
        }
    }

    /// Validates that a `RelationTarget` is not a `contextTier` (which rejects dual pairing).
    private static func assertNotContextTier(_ target: PropertyDefinition.RelationTarget) throws {
        if case .contextTier = target {
            throw DualRelationCoordinatorError.contextTierScopeRejected
        }
    }

    // MARK: - Create paired relation

    /// Creates a paired relation atomically on both sides via `SchemaTransaction`.
    ///
    /// - Parameters:
    ///   - sourceKind: The Type that "owns" the user-facing direction.
    ///   - sourcePropertyName: Display name on the source side (e.g., `"Projects"`).
    ///   - sourceScope: Scope discriminator pointing *at* the target Type.
    ///   - targetKind: The Type the relation points to.
    ///   - targetPropertyName: Display name on the reverse side (e.g., `"Tasks"`).
    ///   - targetScope: Scope discriminator pointing *back* to the source Type.
    ///   - nexus: The active nexus (used for sidecar URL resolution).
    /// - Returns: `(sourcePropertyID, targetPropertyID)` — both freshly minted.
    /// - Throws: `DualRelationCoordinatorError.contextTierScopeRejected` if either scope
    ///   is a `contextTier`. Propagates `SchemaTransactionError` on commit failure.
    @discardableResult
    static func createPairedRelation(
        source sourceKind: TypeKind,
        sourcePropertyName: String,
        sourceScope: PropertyDefinition.RelationTarget,
        target targetKind: TypeKind,
        targetPropertyName: String,
        targetScope: PropertyDefinition.RelationTarget,
        sourceIcon: String? = nil,
        targetIcon: String? = nil,
        nexus: Nexus
    ) throws -> (sourcePropertyID: String, targetPropertyID: String) {
        try assertNotContextTier(sourceScope)
        try assertNotContextTier(targetScope)

        let sourceID = ReservedPropertyID.mintUserPropertyID()
        let targetID = ReservedPropertyID.mintUserPropertyID()

        let sourceDef = PropertyDefinition(
            id: sourceID,
            name: sourcePropertyName,
            type: .relation,
            icon: sourceIcon,
            relationTarget: sourceScope,
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: targetID,
                syncedPropertyDefinedOnTypeID: targetKind.typeID
            )
        )

        let targetDef = PropertyDefinition(
            id: targetID,
            name: targetPropertyName,
            type: .relation,
            icon: targetIcon,
            relationTarget: targetScope,
            dualProperty: PropertyDefinition.DualPropertyConfig(
                syncedPropertyID: sourceID,
                syncedPropertyDefinedOnTypeID: sourceKind.typeID
            )
        )

        var sourceProps = Self.properties(of: sourceKind)
        sourceProps.append(sourceDef)
        var targetProps = Self.properties(of: targetKind)
        targetProps.append(targetDef)

        let updatedSource = Self.replacing(properties: sourceProps, in: sourceKind)
        let updatedTarget = Self.replacing(properties: targetProps, in: targetKind)

        let tx = SchemaTransaction()
        try Self.stage(updatedSource, to: tx, nexus: nexus)
        try Self.stage(updatedTarget, to: tx, nexus: nexus)
        try tx.commit()

        return (sourceID, targetID)
    }

    // MARK: - Rename one side

    /// Renames the display name of one side of a paired relation. Schema-only write —
    /// member files (which store values by property ID) are untouched.
    ///
    /// Only the named side's sidecar is updated; the reverse side keeps its own name.
    static func renameOneSide(
        propertyID: String,
        in ownerKind: TypeKind,
        to newName: String,
        nexus: Nexus
    ) throws {
        var props = Self.properties(of: ownerKind)
        guard let idx = props.firstIndex(where: { $0.id == propertyID }) else {
            throw DualRelationCoordinatorError.propertyNotFound
        }
        props[idx].name = newName
        let updated = Self.replacing(properties: props, in: ownerKind)
        let tx = SchemaTransaction()
        try Self.stage(updated, to: tx, nexus: nexus)
        try tx.commit()
    }

    // MARK: - Delete pair

    /// Deletes both sides of a paired relation atomically and strips all values
    /// from every owning entity on each side.
    ///
    /// - Parameters:
    ///   - propertyID: The ID of one side's property (source or target — order doesn't matter).
    ///   - ownerKind: The Type that owns the property identified by `propertyID`.
    ///   - reverseKind: The Type owning the paired reverse property.
    ///   - nexus: The active nexus.
    ///
    /// Both sidecars are updated and all member-file value-strips are included in a
    /// single `SchemaTransaction` commit.
    static func deletePair(
        propertyID: String,
        owner ownerKind: TypeKind,
        reverse reverseKind: TypeKind,
        nexus: Nexus
    ) throws {
        var ownerProps = Self.properties(of: ownerKind)
        guard let ownerIdx = ownerProps.firstIndex(where: { $0.id == propertyID }) else {
            throw DualRelationCoordinatorError.propertyNotFound
        }
        let ownerDef = ownerProps[ownerIdx]
        ownerProps.remove(at: ownerIdx)

        var reverseProps = Self.properties(of: reverseKind)
        let reverseID = ownerDef.dualProperty?.syncedPropertyID
        let reverseIdx = reverseProps.firstIndex(where: {
            $0.id == reverseID || ($0.dualProperty?.syncedPropertyID == propertyID)
        })
        if let idx = reverseIdx {
            reverseProps.remove(at: idx)
        }

        let updatedOwner = Self.replacing(properties: ownerProps, in: ownerKind)
        let updatedReverse = Self.replacing(properties: reverseProps, in: reverseKind)

        let tx = SchemaTransaction()
        try Self.stage(updatedOwner, to: tx, nexus: nexus)
        try Self.stage(updatedReverse, to: tx, nexus: nexus)

        // Strip property values from owner member files.
        try Self.stageValueStrip(propertyID: propertyID, from: ownerKind, tx: tx, nexus: nexus)

        // Strip reverse property values from reverse member files.
        if let rID = reverseID {
            try Self.stageValueStrip(propertyID: rID, from: reverseKind, tx: tx, nexus: nexus)
        }

        try tx.commit()
    }

    // MARK: - Private: member-file value strip

    /// Stages value-strip rewrites for every member file owned by `kind` that carries
    /// the given `propertyID`. Handles PageType (`.md`), ItemType (`.json`), and
    /// Agenda singletons (`.task.json` / `.event.json`) separately.
    private static func stageValueStrip(
        propertyID: String,
        from kind: TypeKind,
        tx: SchemaTransaction,
        nexus: Nexus
    ) throws {
        switch kind {
        case .pageType(let pt):
            let typeFolder = NexusPaths.vaultFolderURL(forTitle: pt.title, in: nexus)
            let pageFiles = try Filesystem.descendantFiles(
                of: typeFolder,
                where: { $0.pathExtension == "md" }
            )
            MemberFileStrip.forEach(pageFiles) { pageURL in
                var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: pageURL)
                guard fm.properties[propertyID] != nil else { return }
                fm.properties.removeValue(forKey: propertyID)
                let data = try AtomicYAMLMarkdown.encode(frontmatter: fm, body: body)
                tx.stage(payload: data, to: pageURL)
            }

        case .itemType(let it):
            let typeFolder = NexusPaths.itemTypeFolderURL(
                in: nexus.rootURL, typeFolderName: it.title
            )
            let itemFiles = try Filesystem.descendantFiles(
                of: typeFolder,
                where: { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix("_") }
            )
            MemberFileStrip.forEach(itemFiles) { itemURL in
                var item = try AtomicJSON.decode(Item.self, from: itemURL)
                guard item.properties[propertyID] != nil else { return }
                item.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(item), to: itemURL)
            }

        case .agendaTasks:
            let dir = NexusPaths.tasksDir(in: nexus)
            let taskFiles = try Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.taskFileExtension)")
            }
            MemberFileStrip.forEach(taskFiles) { taskURL in
                var task = try AtomicJSON.decode(AgendaTask.self, from: taskURL)
                guard task.properties[propertyID] != nil else { return }
                task.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(task), to: taskURL)
            }

        case .agendaEvents:
            let dir = NexusPaths.eventsDir(in: nexus)
            let eventFiles = try Filesystem.children(of: dir) { url in
                url.lastPathComponent.hasSuffix(".\(NexusPaths.eventFileExtension)")
            }
            MemberFileStrip.forEach(eventFiles) { eventURL in
                var event = try AtomicJSON.decode(AgendaEvent.self, from: eventURL)
                guard event.properties[propertyID] != nil else { return }
                event.properties.removeValue(forKey: propertyID)
                tx.stage(payload: try AtomicJSON.encode(event), to: eventURL)
            }
        }
    }
}

// MARK: - TypeKind convenience

extension DualRelationCoordinator.TypeKind {
    /// The stable identifier of the underlying type. For singleton Agenda schemas
    /// this returns the reserved string identifier rather than a ULID.
    var typeID: String {
        switch self {
        case .pageType(let pt): return pt.id
        case .itemType(let it): return it.id
        case .agendaTasks: return ReservedTypeID.agendaTasks
        case .agendaEvents: return ReservedTypeID.agendaEvents
        }
    }
}
