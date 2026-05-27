import Foundation

/// CRUD methods for Pages across both PageCollection-scoped and
/// Page-Type-root-scoped storage. Split out from `PageContentManager.swift`
/// for legibility. `@MainActor` is inherited from the type declaration;
/// `@Observable` storage is fine across extensions.
///
/// **ParadigmV2 (Task 5.5):** Item CRUD has moved to a parallel
/// `ItemContentManager+CRUD.swift` typed on Item + ItemType + ItemCollection.
///
/// Every CRUD method:
/// - Wraps its body in `do { … } catch { self.pendingError = error; throw error }`
///   so the sidebar toast can surface failures.
/// - For rename methods that do two filesystem ops (rename + save), applies
///   the rename-atomicity rollback pattern; if the revert ALSO fails it
///   surfaces a `RenameAtomicityError`.
extension PageContentManager {

    // MARK: - Page CRUD (PageCollection-scoped)

    @discardableResult
    func createPage(name: String, icon: String? = nil, in collection: PageCollection, vault: PageType) async throws -> PageMeta {
        do {
            let existing = pagesByCollection[collection.id] ?? []
            try PageValidator.validate(
                title: name,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(),
                vault: vault,
                context: contextProvider()
            )

            let now = Date()
            let frontmatter = PageFrontmatter(
                id: ULID.generate(), icon: icon,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now
            )
            let page = PageFile(frontmatter: frontmatter, body: "", title: name)
            let url = NexusPaths.pageFileURL(forTitle: name, in: collection.folderURL)
            try page.save(to: url)

            let meta = PageMeta(id: frontmatter.id, title: name, url: url, frontmatter: frontmatter)
            if let updater = indexUpdater {
                do { try updater.upsertPage(meta, pageTypeID: vault.id, pageCollectionID: collection.id) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(meta)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: collection.pageOrder,
                titleKeyPath: \PageMeta.title
            )
            pagesByCollection[collection.id] = arr
            return meta
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePage(_ page: PageMeta, to newName: String, in collection: PageCollection, vault: PageType) async throws {
        do {
            let existing = pagesByCollection[collection.id] ?? []
            try PageValidator.validate(
                title: newName,
                tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2, tier3: page.frontmatter.tier3,
                properties: page.frontmatter.properties,
                createdAt: page.frontmatter.createdAt,
                vault: vault,
                context: contextProvider()
            )

            let newURL = NexusPaths.pageFileURL(forTitle: newName, in: collection.folderURL)
            // No metadata save here — rename is single-step atomic via
            // FileManager.moveItem. If frontmatter writes are added later,
            // apply the RenameAtomicityError rollback pattern.
            try Filesystem.renameFile(from: page.url, to: newURL)

            var updated = page
            updated.title = newName
            updated.url = newURL

            if let updater = indexUpdater {
                do { try updater.upsertPage(updated, pageTypeID: vault.id, pageCollectionID: collection.id) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == page.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: collection.pageOrder,
                    titleKeyPath: \PageMeta.title
                )
            }
            pagesByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deletePage(_ page: PageMeta, in collection: PageCollection) async throws {
        do {
            try Filesystem.moveToTrash(page.url, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePage(id: page.id) } catch { self.pendingError = error }
            }
            var arr = pagesByCollection[collection.id] ?? []
            arr.removeAll { $0.id == page.id }
            pagesByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
        trashAttachments(for: page.id)
    }

    /// Re-write a Page's body to disk, preserving its frontmatter verbatim.
    /// The editor binds to body only; frontmatter (id, icon, tier1/2/3,
    /// properties, createdAt) round-trips faithfully via PageFile + Yams.
    /// Atomic write happens inside `pageFile.save(to:)` via
    /// `AtomicYAMLMarkdown.write` → `Data.write(.atomic)`.
    ///
    /// In-memory cache (pagesByCollection) is mutated AFTER the disk write
    /// succeeds, so a failed write leaves the cache consistent with disk.
    func updatePage(
        _ page: PageMeta, body: String, in collection: PageCollection, vault: PageType
    )
        async throws
    {
        do {
            let existing = pagesByCollection[collection.id] ?? []
            try PageValidator.validate(
                title: page.title,
                tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2,
                tier3: page.frontmatter.tier3,
                properties: page.frontmatter.properties,
                createdAt: page.frontmatter.createdAt,
                vault: vault,
                context: contextProvider()
            )

            let pageFile = PageFile(frontmatter: page.frontmatter, body: body, title: page.title)
            try pageFile.save(to: page.url)

            if let updater = indexUpdater {
                do { try updater.upsertPage(page, pageTypeID: vault.id, pageCollectionID: collection.id) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == page.id }) {
                // Frontmatter unchanged; body lives only on disk (PageMeta is
                // lightweight tracking — body is loaded on demand via PageFile).
                arr[i] = page
            }
            pagesByCollection[collection.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Page CRUD (Page-Type-root)

    @discardableResult
    func createPage(name: String, icon: String? = nil, inVaultRoot vault: PageType) async throws -> PageMeta {
        do {
            let existing = pagesByTypeRoot[vault.id] ?? []
            try PageValidator.validate(
                title: name,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: Date(),
                vault: vault,
                context: contextProvider()
            )

            let now = Date()
            let frontmatter = PageFrontmatter(
                id: ULID.generate(), icon: icon,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now
            )
            let page = PageFile(frontmatter: frontmatter, body: "", title: name)
            let url = NexusPaths.pageFileURL(forTitle: name, in: folderURL(for: vault))
            try page.save(to: url)

            let meta = PageMeta(id: frontmatter.id, title: name, url: url, frontmatter: frontmatter)
            if let updater = indexUpdater {
                do { try updater.upsertPage(meta, pageTypeID: vault.id, pageCollectionID: nil) } catch { self.pendingError = error }
            }

            var arr = existing
            arr.append(meta)
            arr = OrderResolver.resolve(
                arr,
                persistedOrder: vault.pageOrder,
                titleKeyPath: \PageMeta.title
            )
            pagesByTypeRoot[vault.id] = arr
            return meta
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func renamePage(_ page: PageMeta, to newName: String, inVaultRoot vault: PageType) async throws {
        do {
            let existing = pagesByTypeRoot[vault.id] ?? []
            try PageValidator.validate(
                title: newName,
                tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2, tier3: page.frontmatter.tier3,
                properties: page.frontmatter.properties,
                createdAt: page.frontmatter.createdAt,
                vault: vault,
                context: contextProvider()
            )

            let newURL = NexusPaths.pageFileURL(forTitle: newName, in: folderURL(for: vault))
            // No metadata save here — single-step atomic via FileManager.moveItem.
            try Filesystem.renameFile(from: page.url, to: newURL)

            var updated = page
            updated.title = newName
            updated.url = newURL

            if let updater = indexUpdater {
                do { try updater.upsertPage(updated, pageTypeID: vault.id, pageCollectionID: nil) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == page.id }) {
                arr[i] = updated
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: vault.pageOrder,
                    titleKeyPath: \PageMeta.title
                )
            }
            pagesByTypeRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    func deletePage(_ page: PageMeta, inVaultRoot vault: PageType) async throws {
        do {
            try Filesystem.moveToTrash(page.url, in: nexus)
            if let updater = indexUpdater {
                do { try updater.deletePage(id: page.id) } catch { self.pendingError = error }
            }
            var arr = pagesByTypeRoot[vault.id] ?? []
            arr.removeAll { $0.id == page.id }
            pagesByTypeRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
        trashAttachments(for: page.id)
    }

    /// Best-effort cascade: move a deleted Page's attachments folder to trash.
    /// Shared by every `deletePage` overload. Failures are swallowed — the
    /// attachments folder is non-critical and the SQLite index is regeneratable.
    private func trashAttachments(for pageID: String) {
        let attachmentsURL = NexusPaths.attachmentsDir(for: pageID, in: nexus.rootURL)
        guard FileManager.default.fileExists(atPath: attachmentsURL.path) else { return }
        do { try Filesystem.moveToTrash(attachmentsURL, in: nexus) } catch { /* best-effort */ }
    }

    /// Type-root variant of `updatePage`. Same contract: body-only write,
    /// frontmatter preserved, atomic, in-memory cache mutated after success.
    func updatePage(_ page: PageMeta, body: String, inVaultRoot vault: PageType) async throws {
        do {
            let existing = pagesByTypeRoot[vault.id] ?? []
            try PageValidator.validate(
                title: page.title,
                tier1: page.frontmatter.tier1, tier2: page.frontmatter.tier2,
                tier3: page.frontmatter.tier3,
                properties: page.frontmatter.properties,
                createdAt: page.frontmatter.createdAt,
                vault: vault,
                context: contextProvider()
            )

            let pageFile = PageFile(frontmatter: page.frontmatter, body: body, title: page.title)
            try pageFile.save(to: page.url)

            if let updater = indexUpdater {
                do { try updater.upsertPage(page, pageTypeID: vault.id, pageCollectionID: nil) } catch { self.pendingError = error }
            }

            var arr = existing
            if let i = arr.firstIndex(where: { $0.id == page.id }) {
                arr[i] = page
            }
            pagesByTypeRoot[vault.id] = arr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Move (same-Type, between PageCollections)

    /// Moves `page` from one PageCollection to another within the SAME PageType.
    /// No property strip — both Collections share the same Type schema.
    /// Atomically rewrites the page file at the destination path; on failure the
    /// source remains untouched.
    func movePageBetweenCollections(
        _ page: PageMeta,
        from source: PageCollection,
        to destination: PageCollection,
        in vault: PageType
    ) async throws {
        do {
            let destURL = NexusPaths.pageFileURL(forTitle: page.title, in: destination.folderURL)

            // Load source body so we can rewrite at the new location.
            let pageFile = try PageFile.load(from: page.url)

            // Stage the write at the destination, then move atomically.
            let tx = SchemaTransaction()
            let payload = try AtomicYAMLMarkdown.encode(
                frontmatter: pageFile.frontmatter,
                body: pageFile.body
            )
            tx.stage(payload: payload, to: destURL)
            try tx.commit()

            // Remove source after commit succeeds (SchemaTransaction doesn't delete).
            try Filesystem.deleteFile(at: page.url)

            var updated = page
            updated.url = destURL

            if let updater = indexUpdater {
                do {
                    try updater.upsertPage(updated, pageTypeID: vault.id, pageCollectionID: destination.id)
                } catch {
                    self.pendingError = error
                }
            }

            // Update in-memory caches.
            var srcArr = pagesByCollection[source.id] ?? []
            srcArr.removeAll { $0.id == page.id }
            pagesByCollection[source.id] = srcArr

            var dstArr = pagesByCollection[destination.id] ?? []
            dstArr.append(updated)
            dstArr = OrderResolver.resolve(
                dstArr,
                persistedOrder: destination.pageOrder,
                titleKeyPath: \PageMeta.title
            )
            pagesByCollection[destination.id] = dstArr
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Move (cross-Type, with property strip + paired-relation back-ref clear)

    /// Moves `page` from one PageType (and optional PageCollection) to a different
    /// PageType (and optional PageCollection). Performs:
    ///
    /// 1. **Strip:** property values whose property NAMES don't exist on
    ///    `destination` are removed from the page's frontmatter.
    /// 2. **Paired-relation back-ref clear:** for each relation property with a
    ///    `dualProperty` config that is being stripped (or that points to a
    ///    different Type), the reverse entries on target entities are cleared.
    /// 3. **Atomic commit:** all writes (page rewrite + back-ref clears) go through
    ///    a single `SchemaTransaction`. Any failure rolls the entire set back.
    ///
    /// If `source.id == destination.id`, callers should use
    /// `movePageBetweenCollections` instead (this method enforces the distinction).
    func movePageAcrossTypes(
        _ page: PageMeta,
        from source: PageType,
        fromCollection: PageCollection?,
        to destination: PageType,
        toCollection: PageCollection?
    ) async throws {
        precondition(
            source.id != destination.id,
            "movePageAcrossTypes requires distinct source and destination PageTypes."
        )
        do {
            // 1. Determine strip set by name comparison.
            let destNames = Set(destination.properties.map { $0.name })
            let strippedDefs = source.properties.filter { !destNames.contains($0.name) }
            let strippedIDs = Set(strippedDefs.map { $0.id })

            // 2. Load the page file (frontmatter + body).
            let pageFile = try PageFile.load(from: page.url)
            var updatedFrontmatter = pageFile.frontmatter

            // 3. Strip property values for stripped IDs.
            for id in strippedIDs {
                updatedFrontmatter.properties.removeValue(forKey: id)
            }

            // 4. Compute destination URL.
            let destFolder = toCollection?.folderURL ?? folderURL(for: destination)
            let destURL = NexusPaths.pageFileURL(forTitle: page.title, in: destFolder)

            // 5. Stage the rewritten page at destination.
            let tx = SchemaTransaction()
            let pagePayload = try AtomicYAMLMarkdown.encode(
                frontmatter: updatedFrontmatter,
                body: pageFile.body
            )
            tx.stage(payload: pagePayload, to: destURL)

            // 6. Stage paired-relation back-ref clears for every relation property
            //    that is being stripped and has a dualProperty config.
            for def in strippedDefs where def.type == .relation {
                guard let dual = def.dualProperty else { continue }
                // The reverse property lives on the target Type (page type or item type).
                // Pull the current value from the page's frontmatter (pre-strip).
                guard let value = pageFile.frontmatter.properties[def.id] else { continue }
                // Relation values: single `.relation(id)` or `.multiSelect([id,...])`.
                let targetIDs = Self.extractRelationIDs(from: value)
                guard !targetIDs.isEmpty else { continue }

                // Clear this page's id from each target's reverse property.
                try Self.stageBackRefClear(
                    sourcePageID: page.id,
                    reversePropertyID: dual.syncedPropertyID,
                    onTypeID: dual.syncedPropertyDefinedOnTypeID,
                    targetEntityIDs: targetIDs,
                    tx: tx,
                    nexus: nexus
                )
            }

            // 7. Commit the whole batch atomically.
            try tx.commit()

            // 8. Remove the source file (SchemaTransaction only writes new files).
            try Filesystem.deleteFile(at: page.url)

            // 9. Update index.
            var updated = page
            updated.url = destURL
            updated.frontmatter = updatedFrontmatter
            if let updater = indexUpdater {
                do {
                    try updater.upsertPage(
                        updated,
                        pageTypeID: destination.id,
                        pageCollectionID: toCollection?.id
                    )
                } catch {
                    self.pendingError = error
                }
            }

            // 10. Update in-memory caches — remove from source bucket, add to destination.
            if let srcColl = fromCollection {
                var arr = pagesByCollection[srcColl.id] ?? []
                arr.removeAll { $0.id == page.id }
                pagesByCollection[srcColl.id] = arr
            } else {
                var arr = pagesByTypeRoot[source.id] ?? []
                arr.removeAll { $0.id == page.id }
                pagesByTypeRoot[source.id] = arr
            }

            if let dstColl = toCollection {
                var arr = pagesByCollection[dstColl.id] ?? []
                arr.append(updated)
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: dstColl.pageOrder,
                    titleKeyPath: \PageMeta.title
                )
                pagesByCollection[dstColl.id] = arr
            } else {
                var arr = pagesByTypeRoot[destination.id] ?? []
                arr.append(updated)
                arr = OrderResolver.resolve(
                    arr,
                    persistedOrder: destination.pageOrder,
                    titleKeyPath: \PageMeta.title
                )
                pagesByTypeRoot[destination.id] = arr
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Private move helpers

    /// Extracts target entity IDs from a relation property value.
    /// Handles `.relation(id)` (single) and `.multiSelect([ids])` (multi-pick).
    private static func extractRelationIDs(from value: PropertyValue) -> [String] {
        switch value {
        case .relation(let id): return [id]
        case .multiSelect(let ids): return ids
        default: return []
        }
    }

    /// Stages back-ref clears on files owned by the Type identified by `onTypeID`.
    /// Walks every `.md` (PageType) or `.json` (ItemType) file under that type's
    /// folder and removes `sourcePageID` from the `reversePropertyID` value on
    /// any file whose id appears in `targetEntityIDs`.
    ///
    /// The type is identified purely by folder walk — we don't need a live manager
    /// reference because we're staging filesystem ops, not mutating in-memory state.
    private static func stageBackRefClear(
        sourcePageID: String,
        reversePropertyID: String,
        onTypeID: String,
        targetEntityIDs: [String],
        tx: SchemaTransaction,
        nexus: Nexus
    ) throws {
        let targetSet = Set(targetEntityIDs)

        // Walk all PageType folders looking for the matching type (by sidecar id).
        let nexusRoot = nexus.rootURL
        let allDirs = (try? FileManager.default.contentsOfDirectory(
            at: nexusRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for dir in allDirs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
                  isDir.boolValue
            else { continue }

            // Check for PageType sidecar.
            let ptSidecar = dir.appendingPathComponent(NexusPaths.pageTypeSidecarFilename)
            if FileManager.default.fileExists(atPath: ptSidecar.path) {
                if let pt = try? AtomicJSON.decode(PageType.self, from: ptSidecar),
                   pt.id == onTypeID
                {
                    // Found the target PageType folder — walk .md files.
                    let mdFiles = (try? Filesystem.descendantFiles(
                        of: dir,
                        where: { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("_") }
                    )) ?? []
                    for mdURL in mdFiles {
                        var (fm, body) = try AtomicYAMLMarkdown.load(PageFrontmatter.self, from: mdURL)
                        guard targetSet.contains(fm.id),
                              let val = fm.properties[reversePropertyID]
                        else { continue }
                        let cleared = removeID(sourcePageID, from: val)
                        fm.properties[reversePropertyID] = cleared
                        let data = try AtomicYAMLMarkdown.encode(frontmatter: fm, body: body)
                        tx.stage(payload: data, to: mdURL)
                    }
                    return
                }
            }

            // Check for ItemType sidecar.
            let itSidecar = dir.appendingPathComponent(NexusPaths.itemTypeSidecarFilename)
            if FileManager.default.fileExists(atPath: itSidecar.path) {
                if let it = try? AtomicJSON.decode(ItemType.self, from: itSidecar),
                   it.id == onTypeID
                {
                    // Found the target ItemType folder — walk .json item files.
                    let jsonFiles = (try? Filesystem.descendantFiles(
                        of: dir,
                        where: {
                            $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix("_")
                        }
                    )) ?? []
                    for jsonURL in jsonFiles {
                        var item = try AtomicJSON.decode(Item.self, from: jsonURL)
                        guard targetSet.contains(item.id),
                              let val = item.properties[reversePropertyID]
                        else { continue }
                        let cleared = removeID(sourcePageID, from: val)
                        item.properties[reversePropertyID] = cleared
                        tx.stage(payload: try AtomicJSON.encode(item), to: jsonURL)
                    }
                    return
                }
            }
        }
    }

    /// Removes `idToRemove` from a relation property value.
    /// - `.relation(id)` where id matches → `.null`
    /// - `.multiSelect([ids])` → `.multiSelect` with the id filtered out (nil if empty)
    /// - Other cases → value unchanged
    private static func removeID(_ idToRemove: String, from value: PropertyValue) -> PropertyValue? {
        switch value {
        case .relation(let id):
            return id == idToRemove ? .null : value
        case .multiSelect(let ids):
            let filtered = ids.filter { $0 != idToRemove }
            return filtered.isEmpty ? .null : .multiSelect(filtered)
        default:
            return value
        }
    }

    // MARK: - Update single property value (Task 13 — v0.3.1)

    /// Atomic single-property value write on a Page's frontmatter. Reads the
    /// current PageFile from disk, mutates `properties[propertyID]`, updates
    /// modifiedAt, writes back via PageFile.save (atomic), then refreshes
    /// the in-memory cache + SQLite index entry.
    ///
    /// `newValue == nil` deletes the property key from the frontmatter
    /// (matches "clear cell" / "void this value" UX in the View Settings
    /// cell-editor popovers — Phase H).
    ///
    /// Caller passes `collection: nil` for Page-Type-root-scoped pages and
    /// the matching PageCollection otherwise.
    ///
    /// Dual-relation reverse-mirror via DualRelationCoordinator is deferred
    /// to v0.3.1.x — basic write path lands now; the reverse-side mirror on
    /// relation values surfaces when the relation cell editor wires up at
    /// Task 20 + 21.
    func updatePageProperty(
        _ page: PageMeta,
        propertyID: String,
        newValue: PropertyValue?,
        vault: PageType,
        collection: PageCollection?
    ) async throws {
        do {
            let pageFile = try PageFile.load(from: page.url)
            var fm = pageFile.frontmatter
            if let newValue {
                fm.properties[propertyID] = newValue
            } else {
                fm.properties.removeValue(forKey: propertyID)
            }
            fm.modifiedAt = Date()

            let updatedFile = PageFile(frontmatter: fm, body: pageFile.body, title: page.title)
            try updatedFile.save(to: page.url)

            var updatedMeta = page
            updatedMeta.frontmatter = fm

            if let collection {
                if var arr = pagesByCollection[collection.id],
                   let i = arr.firstIndex(where: { $0.id == page.id })
                {
                    arr[i] = updatedMeta
                    pagesByCollection[collection.id] = arr
                }
            } else {
                if var arr = pagesByTypeRoot[vault.id],
                   let i = arr.firstIndex(where: { $0.id == page.id })
                {
                    arr[i] = updatedMeta
                    pagesByTypeRoot[vault.id] = arr
                }
            }

            if let updater = indexUpdater {
                do {
                    try updater.upsertPage(
                        updatedMeta,
                        pageTypeID: vault.id,
                        pageCollectionID: collection?.id
                    )
                } catch {
                    self.pendingError = error
                }
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }
}
