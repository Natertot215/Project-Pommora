import AppKit
import SwiftUI

/// Production table renderer for the Vault + Collection detail views — a thin
/// `NSViewRepresentable` over a view-based `NSOutlineView`. Replaces the hand-rolled
/// SwiftUI table: disclosure folding, column resize / reorder, alternating row fills,
/// and keyboard navigation are native AppKit, while the per-view column layout
/// (order / width / visibility) persists to the per-view SavedView sidecar. Each cell hosts
/// the existing SwiftUI cell content (`ViewTableCellContent` / `ViewGroupHeaderCell`)
/// via `NSHostingView`, so the chrome is native while cell rendering stays SwiftUI.
///
/// Inputs mirror the pipeline currency (`[ResolvedGroup]` tree + `[ResolvedColumn]`)
/// and the detail view's interaction closures. Native row drag-drop routes the
/// outline's drag-source + drop delegates into the shared `RowDragCoordinator` /
/// `GroupDropPlanner` (reorder / move / rewrite).
struct ViewOutlineTable: NSViewRepresentable {
    /// Private pasteboard type for in-app row drags — an ID-only payload; the
    /// planner resolves reorder vs. move vs. property-rewrite from the drop target.
    static let rowDragType = NSPasteboard.PasteboardType("com.pommora.view-row")

    let groups: [ResolvedGroup]
    let columns: [ResolvedColumn]
    let schema: [PropertyDefinition]

    let index: PommoraIndex?
    let relationResolver: (String) -> (icon: String, title: String)?
    let onDoubleTap: (ViewItem) -> Void
    let commit: (ViewItem, PropertyDefinition, PropertyValue?) -> Void
    let pageMenu: (ViewItem) -> AnyView
    let groupMenu: (ResolvedGroup) -> AnyView

    // Layout persists to the per-view SavedView sidecar (portable + deterministic).
    // The resolver bakes order + width into `columns`, and these write a genuine user
    // drag back to the sidecar (captured by the header `mouseDown`); `ensureColumns`
    // re-applies them on the next rebuild, so a view switch / relaunch restores the
    // arrangement.
    let persistWidth: (_ colID: String, _ width: Double) -> Void
    let persistOrder: (_ newOrder: [String]) -> Void
    /// Column ids the active view hides — applied as native `isHidden` so a hidden
    /// column keeps its width + position instead of being torn out and re-added at a
    /// default width. Never includes the Title.
    let hiddenColumnIDs: Set<String>
    let hideColumn: (_ colID: String) -> Void
    let persistCollapsed: (_ collapsedIDs: [String]) -> Void

    // Drag wiring — the coordinator's commit closures (reorder / move / rewrite)
    // and the view-resolved drop-context builder, consumed by the drop delegates.
    let dragCoordinator: RowDragCoordinator
    let buildDropContext:
        (
            _ draggedItems: [ViewItem], _ targetGroup: ResolvedGroup, _ insertionIndex: Int,
            _ anchorID: String?
        ) -> RowDragCoordinator.DropContext?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let outline = NSOutlineView()
        outline.style = .inset
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsColumnReordering = true
        outline.allowsColumnResizing = true
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.columnAutoresizingStyle = .noColumnAutoresizing
        // Selection is disabled this pass — it competes with row dragging, and
        // multi-select is deferred (it conflicts with drag CRUD). Rows still open
        // on double-click and drag from any row regardless of selection.
        outline.selectionHighlightStyle = .none
        outline.indentationPerLevel = 16
        outline.floatsGroupRows = false
        outline.rowSizeStyle = .custom
        let header = ColumnHeaderView()
        header.coordinator = coordinator
        outline.headerView = header
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.target = coordinator
        outline.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        // Native row drag — only item rows are draggable (the data source returns
        // nil for group headers); `.move` is the only local operation.
        outline.registerForDraggedTypes([ViewOutlineTable.rowDragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)

        coordinator.outlineView = outline
        coordinator.ensureColumns(outline)
        coordinator.applyColumnVisibility(outline)
        coordinator.reload(outline)

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let outline = scroll.documentView as? NSOutlineView else { return }

        // Reconcile the columns whenever the resolved layout's id + kind + title
        // changes — a property added / deleted (set change), renamed (title), or
        // retyped (kind). Hiding is NOT a layout change (that's `isHidden` below),
        // and a pure width change is excluded from the signature so a user resize
        // doesn't trigger a header rebuild. `ensureColumns` adds/removes columns,
        // refreshes header titles in place, and nils the reload signature so the
        // next `reload` re-creates each cell with the new schema. The Title column
        // is never removed, so it can't survive a teardown and duplicate. Order +
        // width persist to the per-view SavedView sidecar (via the header
        // `mouseDown` capture) and `ensureColumns` re-applies them on a rebuild.
        if coordinator.columnLayoutChanged(columns) {
            coordinator.ensureColumns(outline)
        }
        // Hide / show via isHidden (not add/remove) so a hidden column keeps its
        // width + position and restores intact when shown again.
        coordinator.applyColumnVisibility(outline)
        coordinator.reload(outline)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: ViewOutlineTable
        weak var outlineView: NSOutlineView?

        /// The current node tree, rebuilt on each `reload`. `NSOutlineView` holds
        /// nodes by reference, so the value-typed groups/items are wrapped in
        /// reference-typed `OutlineNode`s.
        private var nodes: [OutlineNode] = []

        /// Hash of the last-loaded row structure + content + column layout
        /// (EXCLUDING collapse state) — guards `reload` from re-running `reloadData`
        /// on a collapse toggle, which would fight the native fold animation.
        private var lastSignature: String?

        /// Hash of the column layout (id + kind + title) last reconciled into the
        /// native header by `ensureColumns` — guards `updateNSView` from re-running
        /// `ensureColumns` unless a property is added / deleted / renamed / retyped.
        /// A pure width change is excluded (it persists silently, no header work).
        private var lastColumnSignature: String?

        /// Guards the column + collapse handlers from firing during a programmatic
        /// update (an `ensureColumns` add/remove, or a reload's expansion callbacks),
        /// which would otherwise echo back as a spurious persist.
        private var isApplyingUpdate = false

        /// Native compact row height; the per-column maximum width.
        private static let rowHeight: CGFloat = 24
        private static let maxColumnWidth: CGFloat = 1000

        init(parent: ViewOutlineTable) {
            self.parent = parent
        }

        // MARK: Column setup

        /// Whether the resolved column layout (id + kind + title, NOT width) differs
        /// from what `ensureColumns` last reconciled — the `updateNSView` gate for a
        /// header rebuild. A width-only change returns false (no header work).
        func columnLayoutChanged(_ columns: [ResolvedColumn]) -> Bool {
            Self.columnSignature(of: columns) != lastColumnSignature
        }

        /// Reconciles the native columns to the FULL resolved set WITHOUT a teardown:
        /// adds a column for a new property (in resolved = sidecar order), removes one
        /// for a DELETED property, and refreshes header titles in place. Hiding is NOT
        /// a removal — that is `applyColumnVisibility` (native `isHidden`). Order +
        /// width come from the resolver (the sidecar's `propertyOrder`/`columnWidths`),
        /// so adding in that order restores the saved arrangement on a rebuild.
        ///
        /// The Title column is always present and never removed — the fix for the
        /// duplicated-Title bug: `NSOutlineView` refuses to release the disclosure
        /// (`outlineTableColumn`) column even when detached, so the old total-teardown
        /// left it alive and the re-add produced a SECOND Title. Never removing it
        /// makes the duplicate structurally impossible.
        func ensureColumns(_ outline: NSOutlineView) {
            // Suppress the resize/move handlers while we mutate columns programmatically.
            isApplyingUpdate = true
            defer { isApplyingUpdate = false }
            let desired = parent.columns
            let desiredIDs = Set(desired.map(\.id))

            // Remove only columns whose PROPERTY left the schema (deleted) — never for
            // a hide, never the Title. `tableColumns` is a snapshot, so removing while
            // iterating it is safe.
            for column in outline.tableColumns
            where !desiredIDs.contains(column.identifier.rawValue) {
                outline.removeTableColumn(column)
            }
            // Add new columns; refresh the header label on existing ones (a property
            // rename changes the title without changing the id).
            for resolved in desired {
                let id = NSUserInterfaceItemIdentifier(resolved.id)
                if let existing = outline.tableColumns.first(where: { $0.identifier == id }) {
                    if existing.title != resolved.title { existing.title = resolved.title }
                } else {
                    let column = NSTableColumn(identifier: id)
                    column.title = resolved.title
                    column.minWidth = 60
                    column.maxWidth = Self.maxColumnWidth
                    column.width = CGFloat(resolved.width)
                    outline.addTableColumn(column)
                }
            }
            // The disclosure column is the Title column (always present).
            if let titleColumn = outline.tableColumns.first(where: {
                self.column(for: $0)?.kind == .title
            }) {
                outline.outlineTableColumn = titleColumn
            }
            // A column change must force the next reload (the signature guard would
            // otherwise skip it when only the row structure is unchanged), and record
            // the reconciled layout so `updateNSView` skips redundant ensureColumns.
            lastSignature = nil
            lastColumnSignature = Self.columnSignature(of: desired)
        }

        /// Applies the active view's hidden set as native `column.isHidden`. A hidden
        /// column stays in the table — AppKit keeps autosaving its width + position —
        /// so a hide → show round-trip restores it intact instead of rebuilding it at
        /// a default width. The Title (disclosure) column is never hidden. Forces the
        /// next reload only when a visibility actually flipped (so collapse toggles,
        /// which never touch visibility, still skip the reload and stay jank-free).
        func applyColumnVisibility(_ outline: NSOutlineView) {
            var changed = false
            for column in outline.tableColumns {
                let isTitle = self.column(for: column)?.kind == .title
                let hidden = !isTitle && parent.hiddenColumnIDs.contains(column.identifier.rawValue)
                if column.isHidden != hidden {
                    column.isHidden = hidden
                    changed = true
                }
            }
            if changed { lastSignature = nil }
        }

        // MARK: Node tree

        /// Rebuilds the node tree from the resolved groups, reloads the outline,
        /// and restores expansion from each group's persisted collapse state. The
        /// headerless ungrouped band splices its items in as top-level rows (no
        /// disclosure header), matching the old renderer.
        func reload(_ outline: NSOutlineView) {
            // Skip the reload when the row structure + content AND the column layout
            // are unchanged and only the collapse state differs. Reloading on a
            // collapse toggle re-seeds expansion and fights the native fold animation
            // (the "whole screen janks" symptom), because persisting the toggle
            // re-renders this view. The column hash is folded in so a property
            // rename / type change (same row structure) still forces `reloadData()`,
            // re-creating each cell's hosted content with the new schema + editor.
            let signature = Self.signature(of: parent.groups) + "|" + Self.columnSignature(of: parent.columns)
            guard signature != lastSignature else { return }
            lastSignature = signature

            // `expandItem` (in applyExpansion) fires its expand/collapse delegate
            // callbacks synchronously on macOS, so a synchronous reset is safe — the
            // callbacks all run while `isApplyingUpdate` is still true, which keeps
            // `persistCollapsedState` from echoing the programmatic expansion back as
            // a persist.
            isApplyingUpdate = true
            defer { isApplyingUpdate = false }

            nodes = Self.makeNodes(from: parent.groups)
            outline.reloadData()
            applyExpansion(outline, nodes: nodes)
        }

        private static func makeNodes(from groups: [ResolvedGroup]) -> [OutlineNode] {
            func itemNode(_ item: ViewItem) -> OutlineNode {
                OutlineNode(payload: .item(item))
            }
            func groupNode(_ group: ResolvedGroup) -> OutlineNode {
                let children = group.items.map(itemNode) + (group.children ?? []).map(groupNode)
                return OutlineNode(payload: .group(group), children: children)
            }
            var top: [OutlineNode] = []
            for group in groups {
                if case .ungrouped = group.kind, group.title.isEmpty {
                    top += group.items.map(itemNode)
                    top += (group.children ?? []).map(groupNode)
                } else {
                    top.append(groupNode(group))
                }
            }
            return top
        }

        /// A hash of the row STRUCTURE + content (ids, order, nesting, titles,
        /// modified dates) — deliberately EXCLUDING `isCollapsed`, so a collapse
        /// toggle leaves the signature unchanged and `reload` can skip the
        /// `reloadData` that would otherwise jank the native fold animation.
        private static func signature(of groups: [ResolvedGroup]) -> String {
            var hasher = Hasher()
            func walk(_ group: ResolvedGroup) {
                hasher.combine(group.id)
                hasher.combine(group.title)
                for item in group.items {
                    hasher.combine(item.id)
                    hasher.combine(item.page.title)
                    hasher.combine(item.page.frontmatter.modifiedAt)
                }
                for child in group.children ?? [] { walk(child) }
            }
            for group in groups { walk(group) }
            return String(hasher.finalize())
        }

        /// A hash of the resolved column SCHEMA — id + kind + title only, ORDER- and
        /// width-INDEPENDENT (sorted by id before hashing). Width is excluded so a
        /// user column-resize doesn't force a full `reloadData()` / header rebuild
        /// (it persists silently and re-applies on rebuild); order is excluded so a
        /// user column-reorder (handled natively) doesn't either. A property add /
        /// delete (id-set), rename (title), or type change (kind) DOES change it —
        /// the trigger to refresh stale headers + cell editors.
        private static func columnSignature(of columns: [ResolvedColumn]) -> String {
            var hasher = Hasher()
            for column in columns.sorted(by: { $0.id < $1.id }) {
                hasher.combine(column.id)
                hasher.combine(column.kind)
                hasher.combine(column.title)
            }
            return String(hasher.finalize())
        }

        /// Expands every group whose carried collapse state is open, parent-first
        /// so a child only expands once its parent is visible.
        private func applyExpansion(_ outline: NSOutlineView, nodes: [OutlineNode]) {
            for node in nodes {
                guard case .group(let group) = node.payload else { continue }
                if !group.isCollapsed { outline.expandItem(node) }
                applyExpansion(outline, nodes: node.children)
            }
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? OutlineNode, case .group = node.payload else { return false }
            return !node.children.isEmpty
        }

        private func children(of item: Any?) -> [OutlineNode] {
            guard let node = item as? OutlineNode else { return nodes }
            return node.children
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(
            _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
        ) -> NSView? {
            guard let tableColumn, let node = item as? OutlineNode,
                let column = column(for: tableColumn)
            else { return nil }

            let cell =
                outlineView.makeView(withIdentifier: tableColumn.identifier, owner: self)
                as? HostingCell ?? HostingCell(identifier: tableColumn.identifier)

            switch node.payload {
            case .group(let group):
                // Only the outline (Title) column carries the group label; the
                // rest are blank, like a native folder row.
                if column.kind == .title {
                    cell.host(AnyView(ViewGroupHeaderCell(group: group, menu: parent.groupMenu).id(group.id)))
                } else {
                    cell.host(AnyView(Color.clear))
                }
            case .item(let viewItem):
                cell.host(
                    AnyView(
                        ViewTableCellContent(
                            item: viewItem,
                            column: column,
                            schema: parent.schema,
                            index: parent.index,
                            relationResolver: parent.relationResolver,
                            commit: { [weak self] def, value in self?.parent.commit(viewItem, def, value) },
                            menu: parent.pageMenu
                        ).id(viewItem.id)))
            }
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem _: Any) -> CGFloat {
            Self.rowHeight
        }

        /// Selection is disabled this pass (it competes with dragging; multi-select
        /// is deferred). Rows still open on double-click and drag from any row.
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem _: Any) -> Bool {
            false
        }

        func outlineViewItemDidExpand(_ notification: Notification) { persistCollapsedState() }
        func outlineViewItemDidCollapse(_ notification: Notification) { persistCollapsedState() }

        /// Gathers the currently-collapsed group ids (raw `ResolvedGroup.id`, the
        /// sidecar's `collapsed_groups` vocabulary) and persists the full set.
        private func persistCollapsedState() {
            guard !isApplyingUpdate, let outline = outlineView else { return }
            var collapsed: [String] = []
            func walk(_ node: OutlineNode) {
                if case .group(let group) = node.payload {
                    if !outline.isItemExpanded(node) { collapsed.append(group.id) }
                    for child in node.children { walk(child) }
                }
            }
            for node in nodes { walk(node) }
            parent.persistCollapsed(collapsed)
        }

        // MARK: Actions

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let outline = outlineView else { return }
            let row = outline.clickedRow
            guard row >= 0, let node = outline.item(atRow: row) as? OutlineNode else { return }
            switch node.payload {
            case .item(let viewItem):
                parent.onDoubleTap(viewItem)
            case .group:
                if outline.isItemExpanded(node) {
                    outline.collapseItem(node)
                } else {
                    outline.expandItem(node)
                }
            }
        }

        /// Persists the live column order to the sidecar when it differs from the
        /// resolved order. `NSOutlineView` commits a user column reorder to
        /// `tableColumns` but does NOT post `columnDidMoveNotification`, so the
        /// header view calls this directly once its modal drag-tracking loop returns.
        func persistLiveColumnOrder() {
            guard !isApplyingUpdate, let outline = outlineView else { return }
            let newOrder = outline.tableColumns.map { $0.identifier.rawValue }
            guard newOrder != parent.columns.map(\.id) else { return }
            parent.persistOrder(newOrder)
        }

        /// Persists any user-resized column widths that differ from the resolved
        /// widths. `NSOutlineView` does not reliably post `columnDidResizeNotification`
        /// for a user resize either, so the header view calls this after its tracking
        /// loop, alongside the order capture. `.noColumnAutoresizing` keeps a resize to
        /// the single dragged column, so this normally persists exactly one width.
        func persistLiveColumnWidths() {
            guard !isApplyingUpdate, let outline = outlineView else { return }
            let resolvedWidths = Dictionary(
                parent.columns.map { ($0.id, $0.width) }, uniquingKeysWith: { first, _ in first })
            for column in outline.tableColumns {
                let id = column.identifier.rawValue
                let liveWidth = Double(column.width)
                guard let resolvedWidth = resolvedWidths[id],
                    abs(resolvedWidth - liveWidth) > 0.5
                else { continue }
                parent.persistWidth(id, liveWidth)
            }
        }

        // MARK: Drag & drop

        /// Drag source — only item (page) rows are draggable; group headers return
        /// nil. The pasteboard carries the page id; the planner resolves the rest.
        func outlineView(
            _ outlineView: NSOutlineView, pasteboardWriterForItem item: Any
        ) -> (any NSPasteboardWriting)? {
            guard let node = item as? OutlineNode, case .item(let viewItem) = node.payload
            else { return nil }
            let pbItem = NSPasteboardItem()
            pbItem.setString(viewItem.id, forType: ViewOutlineTable.rowDragType)
            return pbItem
        }

        /// Validate a drop — accept `.move` wherever the proposed position maps to a
        /// real page slot (within / onto a group, or inside the root band), else [].
        func outlineView(
            _ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?, proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard !draggedPageIDs(from: info).isEmpty,
                dropTarget(proposedItem: item, childIndex: index) != nil
            else { return [] }
            return .move
        }

        /// Commit a drop — resolve the destination group + insertion anchor, build
        /// the planner context the detail view owns, and run it through the shared
        /// `RowDragCoordinator` (reorder / move / rewrite, same path as the gallery).
        func outlineView(
            _ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo,
            item: Any?, childIndex index: Int
        ) -> Bool {
            let ids = draggedPageIDs(from: info)
            guard !ids.isEmpty, let target = dropTarget(proposedItem: item, childIndex: index)
            else { return false }
            let dragged = parent.groups.flatMap(\.flattenedItems).filter { ids.contains($0.id) }
            guard !dragged.isEmpty else { return false }
            guard
                let context = parent.buildDropContext(
                    dragged, target.group, target.insertionIndex, target.anchorID)
            else { return false }
            return parent.dragCoordinator.drop(
                payload: ViewRowDragPayload(pageIDs: ids), context: context)
        }

        /// The page ids carried on the drag pasteboard (one per dragged row).
        private func draggedPageIDs(from info: any NSDraggingInfo) -> [String] {
            info.draggingPasteboard.pasteboardItems?
                .compactMap { $0.string(forType: ViewOutlineTable.rowDragType) } ?? []
        }

        /// Maps an `NSOutlineView` drop position onto a planner-ready target: the
        /// destination `ResolvedGroup`, the insertion index WITHIN its `items`, and
        /// the anchor page id the drop lands before (nil = append). Returns nil for a
        /// position with no valid page slot (e.g. between collection headers).
        private func dropTarget(proposedItem item: Any?, childIndex index: Int)
            -> (group: ResolvedGroup, insertionIndex: Int, anchorID: String?)?
        {
            if let node = item as? OutlineNode {
                switch node.payload {
                case .group(let group):
                    // Drop ON the header → append (move into the container). Drop
                    // BETWEEN children → clamp into the items region (child-group
                    // headers sit after items, so an over-range index appends).
                    guard index != NSOutlineViewDropOnItemIndex else {
                        return (group, group.items.count, nil)
                    }
                    let clamped = min(max(index, 0), group.items.count)
                    return (group, clamped, anchorID(in: group, at: clamped))
                case .item(let viewItem):
                    // Drop ON a row → insert before it within its enclosing group.
                    guard let group = enclosingGroup(ofItemID: viewItem.id),
                        let i = group.items.firstIndex(where: { $0.id == viewItem.id })
                    else { return nil }
                    return (group, i, viewItem.id)
                }
            }
            // Root-level drop: the ungrouped band's items render as the trailing
            // top-level rows (after the collection group nodes). Map an index inside
            // that region; reject one that falls among the group headers.
            guard let band = parent.groups.first(where: { $0.kind == .ungrouped }) else { return nil }
            let topGroupNodeCount = nodes.reduce(into: 0) { count, node in
                if case .group = node.payload { count += 1 }
            }
            let local = index - topGroupNodeCount
            guard local >= 0, local <= band.items.count else { return nil }
            return (band, local, anchorID(in: band, at: local))
        }

        /// The page id a drop at `index` within `group.items` lands BEFORE (the
        /// reorder anchor), or nil when `index` is the append slot.
        private func anchorID(in group: ResolvedGroup, at index: Int) -> String? {
            group.items.indices.contains(index) ? group.items[index].id : nil
        }

        /// The resolved group whose `items` contain `id`, searching nested children.
        private func enclosingGroup(ofItemID id: String) -> ResolvedGroup? {
            func search(_ group: ResolvedGroup) -> ResolvedGroup? {
                if group.items.contains(where: { $0.id == id }) { return group }
                for child in group.children ?? [] {
                    if let found = search(child) { return found }
                }
                return nil
            }
            for group in parent.groups {
                if let found = search(group) { return found }
            }
            return nil
        }

        // MARK: Helpers

        /// Builds the right-click header menu for the column at `index` — a single
        /// "Hide Property" item, suppressed for the Title column (never hideable).
        func headerMenu(forColumn index: Int) -> NSMenu? {
            guard let outline = outlineView, outline.tableColumns.indices.contains(index)
            else { return nil }
            let id = outline.tableColumns[index].identifier.rawValue
            guard id != ReservedPropertyID.title else { return nil }
            let menu = NSMenu()
            let item = NSMenuItem(
                title: "Hide Property", action: #selector(hideClickedColumn(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
            return menu
        }

        @objc private func hideClickedColumn(_ sender: NSMenuItem) {
            guard let outline = outlineView, outline.tableColumns.indices.contains(sender.tag)
            else { return }
            let id = outline.tableColumns[sender.tag].identifier.rawValue
            guard id != ReservedPropertyID.title else { return }
            parent.hideColumn(id)
        }

        private func column(for tableColumn: NSTableColumn) -> ResolvedColumn? {
            parent.columns.first { $0.id == tableColumn.identifier.rawValue }
        }
    }
}

// MARK: - Outline node

/// Reference-typed wrapper so `NSOutlineView` (which holds items by reference and
/// tracks expansion by reference identity) can carry the value-typed
/// `ResolvedGroup` / `ViewItem`. Rebuilt on each reload.
private final class OutlineNode {
    enum Payload {
        case group(ResolvedGroup)
        case item(ViewItem)
    }

    let payload: Payload
    let children: [OutlineNode]

    init(payload: Payload, children: [OutlineNode] = []) {
        self.payload = payload
        self.children = children
    }
}

// MARK: - Hosting cell

/// An `NSTableCellView` that hosts a SwiftUI view, swapping its `rootView` on
/// reuse. Pinned to the cell bounds so the SwiftUI content fills the column; the
/// hosting view is transparent, so the table's alternating row fill shows through.
private final class HostingCell: NSTableCellView {
    private var hosting: NSHostingView<AnyView>?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func host(_ view: AnyView) {
        if let hosting {
            hosting.rootView = view
            return
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hosting = hostingView
    }
}

// MARK: - Header view

/// `NSTableHeaderView` subclass that surfaces a right-click "Hide Property" menu
/// for the column under the cursor. The coordinator builds the menu and suppresses
/// it for the non-hideable Title column.
private final class ColumnHeaderView: NSTableHeaderView {
    weak var coordinator: ViewOutlineTable.Coordinator?

    /// `NSTableHeaderView.mouseDown` runs column drag-reorder + resize as a
    /// synchronous modal tracking loop. `NSOutlineView` does NOT post
    /// `columnDidMoveNotification` / `columnDidResizeNotification` for a user
    /// gesture, so once the loop returns (mouse released, move/resize committed to
    /// `tableColumns`) we persist the live order + widths directly. A no-op
    /// (plain click) is filtered by the coordinator's echo guards.
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        coordinator?.persistLiveColumnOrder()
        coordinator?.persistLiveColumnWidths()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let index = column(at: point)
        guard index >= 0 else { return super.menu(for: event) }
        return coordinator?.headerMenu(forColumn: index)
    }
}
