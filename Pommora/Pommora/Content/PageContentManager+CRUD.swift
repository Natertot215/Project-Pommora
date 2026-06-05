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

    // MARK: - Title uniqueness (same-container collision)
    //
    // `PageValidator.validate` owns title shape (empty / invalid chars) + tier
    // + schema checks, but it can't see sibling Pages (it's a pure function with
    // no container view). The same-container collision rule — which prevents a
    // create/rename from silently overwriting another Page's `.md` body — lives
    // here, delegated to the shared `NameCollisionValidator` so Pages + Items
    // enforce one identical rule. Mirrors `ItemContentManager.enforceTitleUniqueness`.
    fileprivate func enforceTitleUniqueness(
        _ desiredTitle: String,
        among siblings: [PageMeta],
        excluding: PageMeta? = nil
    ) throws {
        try NameCollisionValidator.validate(
            desiredTitle: desiredTitle, siblings: siblings, excludingID: excluding?.id,
            else: PageCRUDError.duplicateTitle  // preserve a Page-side contract
        )
    }

    /// Defense-in-depth for the create write path: a freshly-created Page mints
    /// a new id, so any file already at its target URL is owned by a *different*
    /// entity. Refuse the write rather than clobber it — even if a caller ever
    /// skipped `enforceTitleUniqueness` (e.g. a stale in-memory sibling list).
    /// Delegates to the shared `Filesystem.guardNoFile` (Pages / Items / Agenda
    /// share one shape) but keeps the Page-side `duplicateTitle` wording.
    fileprivate func guardNoOverwrite(at url: URL) throws {
        try Filesystem.guardNoFile(at: url, else: PageCRUDError.duplicateTitle)
    }

    // MARK: - Page CRUD (PageCollection-scoped)

    @discardableResult
    func createPage(
        name: String, icon: String? = nil, in collection: PageCollection, vault: PageType
    ) async throws -> PageMeta {
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
            try enforceTitleUniqueness(name, among: existing)

            let now = Date()
            let frontmatter = PageFrontmatter(
                id: ULID.generate(), icon: icon,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now
            )
            let page = PageFile(frontmatter: frontmatter, body: "", title: name)
            let url = NexusPaths.pageFileURL(forTitle: name, in: collection.folderURL)
            try guardNoOverwrite(at: url)
            try page.save(to: url)

            let meta = PageMeta(id: frontmatter.id, title: name, url: url, frontmatter: frontmatter)
            if let updater = indexUpdater {
                do { try updater.upsertPage(meta, pageTypeID: vault.id, pageCollectionID: collection.id) } catch {
                    self.pendingError = error
                }
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
            try enforceTitleUniqueness(newName, among: existing, excluding: page)

            let newURL = NexusPaths.pageFileURL(forTitle: newName, in: collection.folderURL)
            // No metadata save here — rename is single-step atomic via
            // FileManager.moveItem. If frontmatter writes are added later,
            // apply the RenameAtomicityError rollback pattern.
            try Filesystem.renameFile(from: page.url, to: newURL)

            var updated = page
            updated.title = newName
            updated.url = newURL

            if let updater = indexUpdater {
                do { try updater.upsertPage(updated, pageTypeID: vault.id, pageCollectionID: collection.id) } catch {
                    self.pendingError = error
                }
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
                do { try updater.upsertPage(page, pageTypeID: vault.id, pageCollectionID: collection.id) } catch {
                    self.pendingError = error
                }
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
            try enforceTitleUniqueness(name, among: existing)

            let now = Date()
            let frontmatter = PageFrontmatter(
                id: ULID.generate(), icon: icon,
                tier1: [], tier2: [], tier3: [],
                properties: [:],
                createdAt: now
            )
            let page = PageFile(frontmatter: frontmatter, body: "", title: name)
            let url = NexusPaths.pageFileURL(forTitle: name, in: folderURL(for: vault))
            try guardNoOverwrite(at: url)
            try page.save(to: url)

            let meta = PageMeta(id: frontmatter.id, title: name, url: url, frontmatter: frontmatter)
            if let updater = indexUpdater {
                do { try updater.upsertPage(meta, pageTypeID: vault.id, pageCollectionID: nil) } catch {
                    self.pendingError = error
                }
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
            try enforceTitleUniqueness(newName, among: existing, excluding: page)

            let newURL = NexusPaths.pageFileURL(forTitle: newName, in: folderURL(for: vault))
            // No metadata save here — single-step atomic via FileManager.moveItem.
            try Filesystem.renameFile(from: page.url, to: newURL)

            var updated = page
            updated.title = newName
            updated.url = newURL

            if let updater = indexUpdater {
                do { try updater.upsertPage(updated, pageTypeID: vault.id, pageCollectionID: nil) } catch {
                    self.pendingError = error
                }
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
        do { try Filesystem.moveToTrash(attachmentsURL, in: nexus) } catch { /* best-effort */  }
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
                do { try updater.upsertPage(page, pageTypeID: vault.id, pageCollectionID: nil) } catch {
                    self.pendingError = error
                }
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

            // Refuse to clobber a different same-title Page already in the
            // destination. `SchemaTransaction.commit` backs the target up then
            // deletes the backup on success — so without this guard a move would
            // silently destroy the other Page's body (no renameFile here to catch
            // it, unlike rename/moveProject). Page-side `duplicateTitle` wording.
            try guardNoOverwrite(at: destURL)

            // Load source body so we can rewrite at the new location.
            let pageFile = try PageFile.load(from: page.url)

            // Stage the write at the destination, then move atomically.
            let tx = SchemaTransaction()
            let payload = try AtomicYAMLMarkdown.encode(
                frontmatter: pageFile.frontmatter,
                body: pageFile.body,
                preservingFrom: page.url,
                modeledKeys: PageFrontmatter.modeledKeys
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

    // MARK: - Move (cross-Type, with property strip)

    /// Moves `page` from one PageType (and optional PageCollection) to a different
    /// PageType (and optional PageCollection). Performs:
    ///
    /// 1. **Strip:** property values whose property NAMES don't exist on
    ///    `destination` are removed from the page's frontmatter.
    /// 2. **Atomic commit:** all writes go through a single `SchemaTransaction`.
    ///    Any failure rolls the entire set back.
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

            // 4a. Refuse to clobber a different same-title Page already in the
            //     destination Type/Collection (same data-loss vector as the
            //     between-Collections move — SchemaTransaction would back up + drop
            //     the existing file). Page-side `duplicateTitle` wording.
            try guardNoOverwrite(at: destURL)

            // 5. Stage the rewritten page at destination.
            let tx = SchemaTransaction()
            let pagePayload = try AtomicYAMLMarkdown.encode(
                frontmatter: updatedFrontmatter,
                body: pageFile.body,
                preservingFrom: page.url,
                modeledKeys: PageFrontmatter.modeledKeys
            )
            tx.stage(payload: pagePayload, to: destURL)

            // 6. Commit the whole batch atomically.
            try tx.commit()

            // 7. Remove the source file (SchemaTransaction only writes new files).
            try Filesystem.deleteFile(at: page.url)

            // 8. Update index.
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

            // 9. Update in-memory caches — remove from source bucket, add to destination.
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
            if case .relation(let ids)? = newValue {
                fm.setRelationIDs(ids, forPropertyID: propertyID)  // tier→root, user→properties, empty→omit
            } else if let newValue {
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

    /// Persists a wholesale frontmatter replacement for a page (all properties +
    /// tiers), preserving the on-disk body. The Page inspector edits the full
    /// frontmatter as a debounced draft and flushes it here; `updatePageProperty`
    /// remains the granular per-key path (table cells). Mirrors that method's
    /// load → mutate → atomic-save → cache-refresh → best-effort index-upsert shape.
    func updatePageFrontmatter(
        _ page: PageMeta,
        frontmatter: PageFrontmatter,
        vault: PageType,
        collection: PageCollection?
    ) async throws {
        do {
            let pageFile = try PageFile.load(from: page.url)
            var fm = frontmatter
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
                        updatedMeta, pageTypeID: vault.id, pageCollectionID: collection?.id)
                } catch {
                    self.pendingError = error
                }
            }
        } catch {
            self.pendingError = error
            throw error
        }
    }

    // MARK: - Update icon

    /// Persists a new icon onto a Page's frontmatter — sets `icon` on a copy of
    /// the current frontmatter and routes through `updatePageFrontmatter`, which
    /// atomically rewrites the `.md` (preserving the body + bumping `modifiedAt`),
    /// refreshes the in-memory cache, and re-indexes.
    func updatePageIcon(_ page: PageMeta, to icon: String?, vault: PageType, collection: PageCollection?) async throws {
        var fm = page.frontmatter
        fm.icon = icon
        try await updatePageFrontmatter(page, frontmatter: fm, vault: vault, collection: collection)
    }

    // MARK: - Context-delete cascade (Phase 18b)

    /// Removes a deleted Context's ID from the `tier` array of every Page that
    /// references it. Source-side cascade: invoked at the Context-delete call
    /// site (×4, once per content manager) **before** the Context file is removed.
    ///
    /// `index` is queried via `IndexQuery.incomingRelations(targetID:)` (which
    /// reads the `relations` table — tier links are mirrored there for all four
    /// entity kinds). Each Page that references `contextID` is located from the
    /// index (no in-hand URL), loaded, mutated through the `setRelationIDs`
    /// adapter (tiers route to the frontmatter root, NOT `properties["_tierN"]`),
    /// atomically rewritten, its in-memory cache entry refreshed if loaded, and
    /// re-indexed so the stale `relations` rows reconcile away.
    ///
    /// Resilient per-entity: a Page that can't be located or loaded is skipped so
    /// one bad file doesn't abort the cascade. The first such failure is recorded
    /// on `pendingError` (matching the manager's best-effort index-write discipline)
    /// but never thrown — the cascade always runs to completion across the rest.
    func unlinkTier(contextID: String, tier: Int, index: PommoraIndex) async throws {
        guard let tierPropID = ReservedPropertyID.tierPropertyID(forTier: tier) else { return }

        let refs = try await IndexQuery(index).incomingRelations(targetID: contextID)
        let pageRefs = refs.filter { $0.kind == .page }

        for ref in pageRefs {
            do {
                guard
                    let container = try await IndexQuery(index)
                        .entityContainer(id: ref.id, kind: .page),
                    let url = locatePageFile(id: ref.id, container: container)
                else { continue }

                var pageFile = try PageFile.load(from: url)
                let current = pageFile.frontmatter.relationIDs(forPropertyID: tierPropID)
                guard current.contains(contextID) else { continue }

                let newIDs = current.filter { $0 != contextID }
                pageFile.frontmatter.setRelationIDs(newIDs, forPropertyID: tierPropID)
                pageFile.frontmatter.modifiedAt = Date()

                let updatedFile = PageFile(
                    frontmatter: pageFile.frontmatter, body: pageFile.body, title: pageFile.title
                )
                try updatedFile.save(to: url)

                let updatedMeta = PageMeta(
                    id: ref.id, title: pageFile.title, url: url, frontmatter: pageFile.frontmatter
                )
                refreshPageCache(updatedMeta, container: container)

                if let updater = indexUpdater {
                    do {
                        try updater.upsertPage(
                            updatedMeta,
                            pageTypeID: container.typeID,
                            pageCollectionID: container.collectionID
                        )
                    } catch {
                        self.pendingError = error
                    }
                }
            } catch {
                // Continue-on-individual-failure: a single unreadable / unwritable
                // Page must not block the rest of the cascade.
                self.pendingError = error
                continue
            }
        }
    }

    /// Locates a Page's `.md` file from its index container. The folder is built
    /// from the container titles; the file is found by walking that folder and
    /// matching `frontmatter.id` — nesting-proof for Type-root Pages that
    /// physically live in a deeper non-Collection sub-folder (whose files roll up
    /// to the Type root with `page_collection_id == nil`).
    private func locatePageFile(id: String, container: EntityContainer) -> URL? {
        let folder: URL
        if let collectionTitle = container.collectionTitle {
            folder = NexusPaths.pageCollectionFolderURL(
                in: nexus.rootURL,
                typeFolderName: container.typeTitle,
                collectionFolderName: collectionTitle
            )
        } else {
            folder = NexusPaths.pageTypeFolderURL(
                in: nexus.rootURL, typeFolderName: container.typeTitle
            )
        }
        let candidate = NexusPaths.pageFileURL(forTitle: container.entityTitle, in: folder)
        if Filesystem.fileExists(at: candidate),
            let fm = try? PageFile.load(from: candidate).frontmatter,
            fm.id == id
        {
            return candidate
        }
        // Fall back to a descendant walk matching by id (handles nested Type-root
        // Pages + any title/filename divergence).
        let matches =
            (try? Filesystem.descendantFiles(of: folder) { url in
                url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_")
            }) ?? []
        for url in matches {
            if let fm = try? PageFile.load(from: url).frontmatter, fm.id == id {
                return url
            }
        }
        return nil
    }

    /// Refreshes the in-memory `PageMeta` for `updated` in whichever cache bucket
    /// holds it (Collection-scoped or Type-root), if present. No-op when the Page
    /// isn't loaded — the on-disk write + index upsert are the source of truth.
    private func refreshPageCache(_ updated: PageMeta, container: EntityContainer) {
        if let collectionID = container.collectionID {
            if var arr = pagesByCollection[collectionID],
                let i = arr.firstIndex(where: { $0.id == updated.id })
            {
                arr[i] = updated
                pagesByCollection[collectionID] = arr
            }
        } else {
            if var arr = pagesByTypeRoot[container.typeID],
                let i = arr.firstIndex(where: { $0.id == updated.id })
            {
                arr[i] = updated
                pagesByTypeRoot[container.typeID] = arr
            }
        }
    }
}

/// Errors surfaced by `PageContentManager` create/rename when a same-container
/// name collision would silently overwrite another Page's `.md` body. Mirrors
/// `ItemCRUDError.duplicateTitle` so Pages + Items reject collisions identically
/// (locked decision — no auto-rename, no overwrite). Title shape (empty /
/// invalid characters) is owned by `PageValidator`; this covers the sibling
/// collision only.
enum PageCRUDError: Error, LocalizedError, Equatable {
    case duplicateTitle

    var errorDescription: String? {
        switch self {
        case .duplicateTitle: return "A Page with that name already exists."
        }
    }
}
