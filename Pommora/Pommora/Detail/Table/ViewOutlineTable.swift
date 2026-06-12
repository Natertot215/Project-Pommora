import AppKit
import SwiftUI

/// Production table renderer for the Vault + Collection detail views — a thin
/// `NSViewRepresentable` over a view-based `NSOutlineView`. Replaces the
/// hand-rolled SwiftUI table: disclosure folding, column resize / reorder /
/// width-persistence, alternating row fills, selection, and keyboard navigation
/// are all native AppKit behavior. Each cell hosts the existing SwiftUI cell
/// content (`ViewTableCellContent` / `ViewGroupHeaderCell`) via `NSHostingView`,
/// so the column chrome is native while cell rendering stays SwiftUI.
///
/// Inputs mirror the pipeline currency (`[ResolvedGroup]` tree + `[ResolvedColumn]`)
/// and the detail view's interaction closures — a drop-in for the old renderer.
/// Row drag-drop is wired natively in a follow-up pass (`dragCoordinator` /
/// `buildDropContext` are carried for that step).
struct ViewOutlineTable: NSViewRepresentable {
    let groups: [ResolvedGroup]
    let columns: [ResolvedColumn]
    let schema: [PropertyDefinition]

    let index: PommoraIndex?
    let relationResolver: (String) -> (icon: String, title: String)?
    let onDoubleTap: (ViewItem) -> Void
    let commit: (ViewItem, PropertyDefinition, PropertyValue?) -> Void
    let pageMenu: (ViewItem) -> AnyView
    let groupMenu: (ResolvedGroup) -> AnyView

    let persistWidth: (_ colID: String, _ width: Double) -> Void
    let persistOrder: (_ newOrder: [String]) -> Void
    let hideColumn: (_ colID: String) -> Void
    let persistCollapsed: (_ collapsedIDs: [String]) -> Void

    // Drag wiring — carried now, consumed when native row drag-drop lands.
    let dragCoordinator: RowDragCoordinator
    let buildDropContext:
        (
            _ draggedItems: [ViewItem], _ targetGroup: ResolvedGroup, _ insertionIndex: Int,
            _ anchorID: String?, _ sourceIndices: IndexSet
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

        coordinator.outlineView = outline
        coordinator.rebuildColumns(outline)
        coordinator.reload(outline)

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false

        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(Coordinator.columnDidResize(_:)),
            name: NSTableView.columnDidResizeNotification, object: outline)
        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(Coordinator.columnDidMove(_:)),
            name: NSTableView.columnDidMoveNotification, object: outline)

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let outline = scroll.documentView as? NSOutlineView else { return }

        // Rebuild columns only when their identity/order changed — a width-only
        // resize keeps the same ids, so the live geometry survives an update.
        let currentIDs = outline.tableColumns.map { $0.identifier.rawValue }
        if currentIDs != columns.map(\.id) {
            coordinator.rebuildColumns(outline)
        }
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

        /// Hash of the last-loaded row structure + content (EXCLUDING collapse
        /// state) — guards `reload` from re-running `reloadData` on a collapse
        /// toggle, which would fight the native fold animation.
        private var lastSignature: String?

        /// Guards the notification handlers from firing during programmatic
        /// reloads (which would echo back as spurious persists).
        private var isApplyingUpdate = false

        /// Held TRUE across a column rebuild AND the following runloop tick, so the
        /// `columnDidMove` notifications AppKit posts asynchronously when columns are
        /// removed don't echo back as a `persistOrder` that wipes the saved layout
        /// (the "hiding a property resets order + sizing" bug).
        private var isRebuildingColumns = false

        /// Coalesces the stream of resize notifications into one persist after the
        /// drag settles (a raw per-notification write would churn the sidecar).
        private var pendingWidths: [String: Double] = [:]
        private var widthFlush: DispatchWorkItem?

        /// Native compact row height; the per-column maximum width.
        private static let rowHeight: CGFloat = 24
        private static let maxColumnWidth: CGFloat = 1000

        init(parent: ViewOutlineTable) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: Column setup

        /// Tears down and rebuilds the native columns from the resolved set, then
        /// points the disclosure (outline) column at the Title column wherever it
        /// sits in the order. Called on first build + whenever the column identity
        /// or order changes.
        func rebuildColumns(_ outline: NSOutlineView) {
            isRebuildingColumns = true
            // Reset on the NEXT runloop tick (not synchronously) so any column move/
            // resize notifications AppKit posts asynchronously from this rebuild stay
            // suppressed — otherwise they echo back as a persistOrder/persistWidth
            // that wipes the saved column layout.
            defer { DispatchQueue.main.async { [weak self] in self?.isRebuildingColumns = false } }

            // Detach the outline (disclosure) column BEFORE clearing. AppKit keeps
            // `outlineTableColumn` alive across `removeTableColumn`, so leaving it
            // set lets the old Title column survive the rebuild and reappear as a
            // duplicate once the fresh Title column is re-added (the duplicated-
            // Title bug after an async column change, e.g. tier columns loading).
            outline.outlineTableColumn = nil
            // Total teardown — re-read `tableColumns` each step so NO column survives
            // (not even a former outline column AppKit might retain). A snapshot loop
            // can leave one behind, which then duplicates on re-add. The bound guards
            // the main thread against any column that declines removal.
            var safety = 0
            while let last = outline.tableColumns.last, safety < 128 {
                outline.removeTableColumn(last)
                safety += 1
            }

            // Re-add the resolved columns, deduped by identifier: two NSTableColumns
            // sharing an id both resolve to the same kind and render the same cell
            // (the duplicated-Title symptom), so each id is added at most once.
            var addedIDs = Set<String>()
            for resolved in parent.columns where addedIDs.insert(resolved.id).inserted {
                let column = NSTableColumn(identifier: .init(resolved.id))
                column.title = resolved.title
                column.width = CGFloat(resolved.width)
                column.minWidth = 60
                column.maxWidth = Self.maxColumnWidth
                outline.addTableColumn(column)
            }
            let titleColumn = outline.tableColumns.first { column in
                self.column(for: column)?.kind == .title
            }
            outline.outlineTableColumn = titleColumn ?? outline.tableColumns.first

            // A column change must force the next reload (the signature guard would
            // otherwise skip it when only the row structure is unchanged).
            lastSignature = nil

            #if DEBUG
            if outline.tableColumns.count != parent.columns.count {
                print(
                    "[ViewOutlineTable] COLUMN MISMATCH resolved=\(parent.columns.count) "
                        + "actual=\(outline.tableColumns.count): "
                        + outline.tableColumns.map(\.identifier.rawValue).joined(separator: ","))
            }
            #endif
        }

        // MARK: Node tree

        /// Rebuilds the node tree from the resolved groups, reloads the outline,
        /// and restores expansion from each group's persisted collapse state. The
        /// headerless ungrouped band splices its items in as top-level rows (no
        /// disclosure header), matching the old renderer.
        func reload(_ outline: NSOutlineView) {
            // Skip the reload when the row structure + content is unchanged and only
            // the collapse state differs. Reloading on a collapse toggle re-seeds
            // expansion and fights the native fold animation (the "whole screen
            // janks" symptom), because persisting the toggle re-renders this view.
            let signature = Self.signature(of: parent.groups)
            guard signature != lastSignature else { return }
            lastSignature = signature

            // `expandItem` (in applyExpansion) fires its expand/collapse delegate
            // callbacks synchronously on macOS, so a synchronous reset is safe — the
            // callbacks all run while `isApplyingUpdate` is still true and are
            // suppressed. (If that ever became async, this would need the same
            // next-tick reset that `isRebuildingColumns` uses.)
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

        // MARK: Actions & notifications

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

        @objc func columnDidResize(_ notification: Notification) {
            guard !isApplyingUpdate, !isRebuildingColumns,
                let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn
            else { return }
            let id = column.identifier.rawValue
            let newWidth = Double(column.width)
            // Persist only a GENUINE user resize. A rebuild re-adds columns at their
            // resolved (already-persisted) widths, which echoes a resize notification;
            // if the width already matches the resolved value it's an echo, not a
            // drag, and writing it back would churn — or wipe — the saved layout.
            guard let resolved = parent.columns.first(where: { $0.id == id }),
                abs(resolved.width - newWidth) > 0.5
            else { return }
            scheduleWidthPersist(id, newWidth)
        }

        @objc func columnDidMove(_ notification: Notification) {
            guard !isApplyingUpdate, !isRebuildingColumns, let outline = outlineView else { return }
            let newOrder = outline.tableColumns.map { $0.identifier.rawValue }
            // Persist only a GENUINE user reorder. A rebuild re-adds columns in the
            // resolved order, echoing a move notification; if the visual order already
            // matches the resolved order it's an echo, not a drag, so writing it back
            // would overwrite the saved propertyOrder with the default layout.
            guard newOrder != parent.columns.map(\.id) else { return }
            parent.persistOrder(newOrder)
        }

        /// Debounced width persist — the final width after the resize settles.
        private func scheduleWidthPersist(_ id: String, _ width: Double) {
            pendingWidths[id] = width
            widthFlush?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                for (colID, value) in self.pendingWidths { self.parent.persistWidth(colID, value) }
                self.pendingWidths.removeAll()
            }
            widthFlush = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
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

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let index = column(at: point)
        guard index >= 0 else { return super.menu(for: event) }
        return coordinator?.headerMenu(forColumn: index)
    }
}
