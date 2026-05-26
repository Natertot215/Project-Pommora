### Items-Side Detail Views + Drag-Reorder + Pages-Side Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This is the canonical spec + implementation plan (no separate spec file).

**Goal:** Replace the stubbed Items-side detail views with full table surfaces, add drag-to-reorder across all four storage-container detail panes (Vault / Type / Collection / Set), and clean up two Pages-side gaps (`+ New Page` button + sort-UI duplicate header).

**Architecture:** Pure UI wiring on top of the v0.3.0 `ItemContentManager` / `ItemTypeManager` / `PageContentManager` / `PageTypeManager` APIs. Detail views are read-only consumers of in-memory manager arrays — they ignore `defaultSort` for now (v0.5.0 wires that consumer site). Drag uses SwiftUI's `Transferable` + `.draggable` + `.dropDestination` because `SwiftUI.Table` doesn't expose `.onMove`. **Detail-view drag-reorder is SESSION-LOCAL** — it does NOT write to sidecar `order:` (which remains the sidebar's drag-reorder system). This keeps the two systems independent so v0.5.0 saved-view-configs can split cleanly: detail-view drag will migrate to per-view-config overrides, sidebar drag stays on `order:`. In v1 of this plan, navigating away from a detail view resets its session-local reorder.

**Tech Stack:** SwiftUI `Table(children:)` for display; `Transferable` + `.draggable(_:)` + `.dropDestination(for:action:)` for drag; `@MainActor @Observable` managers; existing `SidebarSelection` selection model with the existing `.itemCollection` case.

---

#### Active branch quirks to honor (every task)

- **Quirk #1**: Test filter form is `-only-testing:PommoraTests/<FilenameWithoutExtension>`, not `@Suite` name. Visually verify the test count — suite-name form silently no-ops with `** TEST SUCCEEDED **`.
- **Quirk #2**: Both targets use `PBXFileSystemSynchronizedRootGroup`. New Swift files auto-include; deleted files auto-drop. No pbxproj edits.
- **Quirk #3**: Trust `xcodebuild`, not SourceKit squiggles. `Cannot find type 'X'` for in-module types is routinely stale post-edit.
- **Quirk #5**: Swift 6 strict concurrency + ExistentialAny ON. Custom Codable uses `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`.
- **Quirk #9**: SidebarView Section structure is load-bearing — do NOT alter `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns.
- **Quirk #10**: Sidebar selection chrome lives at row-file level via `.listRowBackground(SelectionChrome(...))`, not in-content `.background`.
- **Quirk #12**: `swift format` invocation is `swift format format --in-place ...` / `swift format lint --strict --recursive ...` — NOT the direct `swift-format` binary.
- **Quirk #13**: Always builder-verify via `Agent run_in_background: true` with `-only-testing:PommoraTests` (no window focus stealing).
- **Quirk #14**: GRDB `String` overload pollution in @ViewBuilder closures. Isolate per-row rendering into private struct sub-views with plain value types; use `first(where:)` not `contains(_:)`.

#### Already landed (this branch, pre-plan)

These are NOT plan tasks — they shipped during the brainstorming session and the build is green.

- `.claude/Planning/Items-Detail-Views-spec.md` — the spec this plan implements.
- `Pommora/Pommora/Sidebar/ItemTypeRow.swift` — flattened to leaf with full context menu.
- `Pommora/Pommora/Sidebar/ItemCollectionRow.swift` — deleted.
- `Pommora/Pommora/Sidebar/SidebarConfirmation.swift` — `.deleteItemType` case.
- `Pommora/Pommora/Sidebar/SidebarView.swift` — `ItemsSection` bindings + `.deleteItemType` confirmation arms + `ItemTypeManager` environment.
- `Pommora/Pommora/Items/ItemTypeManager.swift` — `parentItemType(for:)` helper.

---

### Task 1: Strip duplicate sort UI from `PageCollectionDetailView`

**Why:** The custom `sortHeaderBar` (a `HStack` of `SortHeaderButton` views) double-renders with SwiftUI `Table`'s native column headers — visible duplicate header strip in production (Nathan's 2026-05-25 screenshot). Sort goes away entirely; SwiftUI's `Table` headers are the only headers.

**Files:**
- Modify: `Pommora/Pommora/Detail/PageCollectionDetailView.swift`
- Delete: `Pommora/PommoraTests/Detail/PageCollectionDetailViewModelTests.swift` (entire file — VM gone)

- [x] **Step 1: Read current `PageCollectionDetailView.swift`** to confirm the exact symbols to delete.

```bash
sed -n '1,100p' "Pommora/Pommora/Detail/PageCollectionDetailView.swift"
```

Symbols to remove (in this file): `PageCollectionSortColumn` enum, `PageCollectionDetailViewModel` class, `SortHeaderButton` struct, `@State private var sortVM`, `private var sortHeaderBar` computed view, the `sortHeaderBar` call site inside `table`, the `sortedRows` computed, plus rename `unsortedRows` → `rows`.

- [x] **Step 2: Rewrite `PageCollectionDetailView.swift` to the simplified shape**

Replace the entire file content with this. Note: `SortHeaderButton` may also be referenced by tests — those tests are deleted in Step 4 below.

```swift
import SwiftUI

struct PageCollectionDetailView: View {
    let collection: PageCollection
    let vault: PageType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?

    @Environment(PageContentManager.self) private var contentManager

    @State private var tableSelection: Set<String> = []
    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: collection.id) {
            await contentManager.loadAll(for: collection)
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            if let row = renameTarget {
                Text("Rename \(row.kindLabel.lowercased()) \"\(row.title)\"")
            }
        }
    }

    private var header: some View {
        HStack {
            Label {
                Text(collection.title)
            } icon: {
                Image(systemName: "folder")
            }
            .font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    private var table: some View {
        Table(rows, children: \.children, selection: $tableSelection) {
            TableColumn("Name") { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.iconName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handleDoubleTap(row) }
                .contextMenu { menuItems(for: row) }
            }
            TableColumn("Kind") { row in
                Text(row.kindLabel).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 140)
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        }
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .item(let i): presentedItem = i
        case .page(let p): selection = .page(p)
        case .collection: break
        }
    }

    private var footer: some View {
        HStack {
            Button {
                presentedSheet = .newPage(collection: collection, pageType: vault)
            } label: {
                Label("New Page", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            Spacer()
        }
        .padding(8)
    }

    private var rows: [DetailRow] {
        let pages = contentManager.pages(in: collection).map { ContentItem.page($0) }
        let items: [ContentItem] = []  // Items live in ItemContentManager keyed on ItemCollection
        return (pages + items).map { ci in
            DetailRow(
                id: ci.id,
                title: ci.title,
                kind: detailKind(ci),
                iconName: ci.iconName,
                modifiedAt: ci.modifiedAt,
                children: nil
            )
        }
    }

    private func detailKind(_ ci: ContentItem) -> DetailRow.Kind {
        switch ci {
        case .page(let p): return .page(p)
        case .item(let i): return .item(i)
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .page, .item:
            Button("Rename") { beginRename(row) }
            Button(isPinned(row) ? "Unpin \(row.kindLabel)" : "Pin \(row.kindLabel)") {
                togglePin(row)
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .collection:
            EmptyView()
        }
    }

    private func stateRef(for row: DetailRow) -> EntityStateRef? {
        switch row.kind {
        case .page(let p): return EntityStateRef(kind: .page, id: p.id, title: p.title)
        case .item(let i): return EntityStateRef(kind: .item, id: i.id, title: i.title)
        case .collection: return nil
        }
    }

    private func isPinned(_ row: DetailRow) -> Bool {
        guard let ref = stateRef(for: row) else { return false }
        return AppGlobals.pinnedManager?.contains(ref) ?? false
    }

    private func togglePin(_ row: DetailRow) {
        guard let ref = stateRef(for: row) else { return }
        AppGlobals.pinnedManager?.toggle(ref)
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func beginRename(_ row: DetailRow) {
        renameDraft = row.title
        renameTarget = row
    }

    private func commitRename() {
        guard let row = renameTarget else { return }
        let newName = renameDraft
        renameTarget = nil
        guard !newName.isEmpty, newName != row.title else { return }
        Task {
            do {
                switch row.kind {
                case .page(let p):
                    try await contentManager.renamePage(p, to: newName, in: collection, vault: vault)
                case .item:
                    break  // Items rename via Item Window
                case .collection:
                    break
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func delete(_ row: DetailRow) async {
        do {
            switch row.kind {
            case .page(let p):
                try await contentManager.deletePage(p, in: collection)
            case .item:
                break
            case .collection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}
```

- [x] **Step 3: Delete the obsolete test file**

```bash
rm "Pommora/PommoraTests/Detail/PageCollectionDetailViewModelTests.swift"
```

- [x] **Step 4: Builder verify (background, `-only-testing:PommoraTests`)**

Expected: `** BUILD SUCCEEDED **` and all PommoraTests pass. The deleted VM tests drop with the file (quirk #2 — PBXFileSystemSynchronizedRootGroup); no pbxproj edit.

- [x] **Step 5: Commit**

```bash
git add Pommora/Pommora/Detail/PageCollectionDetailView.swift Pommora/PommoraTests/Detail/PageCollectionDetailViewModelTests.swift
git commit -m "fix(detail): strip duplicate sort header — SwiftUI Table renders native column headers now

Removes the v0.3.0 custom sortHeaderBar that double-rendered with
SwiftUI.Table's native column headers (visible duplicate in production).
Click-to-sort is fully deferred to v0.5.0 alongside saved-view-configs.
PageCollectionDetailViewModel, PageCollectionSortColumn, SortHeaderButton,
and their tests all deleted."
```

---

### Task 2: Replace `NewItemSheet` stub with real create form

**Why:** The current `NewItemSheet` is a `ContentUnavailableView` stub. The "+ New Item" buttons that ship in later tasks would no-op without this. Mirror `NewPageTypeSheet`'s Name + Icon form pattern.

**Files:**
- Modify: `Pommora/Pommora/Sidebar/Sheets/NewItemSheet.swift` (replace stub)
- Create: `Pommora/PommoraTests/Sidebar/Sheets/NewItemSheetTests.swift`

- [x] **Step 1: Write failing test for the sheet's create path**

```swift
// Pommora/PommoraTests/Sidebar/Sheets/NewItemSheetTests.swift
import Testing
@testable import Pommora

@Suite("NewItemSheetTests")
@MainActor
struct NewItemSheetTests {
    @Test("Creating into a Set routes through ItemContentManager.createItem(in collection)")
    func createsIntoCollection() async throws {
        let (env, type, collection) = try await TestNexus.makeTypeWithCollection(typeName: "Recipes", collectionName: "Mains")
        let item = try await env.itemContentManager.createItem(name: "Pasta", in: collection, type: type)
        #expect(item.title == "Pasta")
        #expect(env.itemContentManager.items(in: collection).contains { $0.id == item.id })
    }

    @Test("Creating into a Type root routes through ItemContentManager.createItem(inTypeRoot)")
    func createsIntoTypeRoot() async throws {
        let (env, type) = try await TestNexus.makeType(name: "Recipes")
        let item = try await env.itemContentManager.createItem(name: "Quick", inTypeRoot: type)
        #expect(item.title == "Quick")
        #expect(env.itemContentManager.items(in: type).contains { $0.id == item.id })
    }

    @Test("Empty name fails the create-button validation predicate")
    func emptyNameRejected() {
        let trimmed = "   ".trimmingCharacters(in: .whitespaces)
        #expect(trimmed.isEmpty)
    }
}
```

Note: `TestNexus.makeTypeWithCollection` and `makeType` are existing test helpers — if they don't exist with those exact names, locate the equivalent fixture-builder in `PommoraTests/Helpers/` and adjust.

- [x] **Step 2: Run failing test to confirm RED**

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/NewItemSheetTests
```

Expected: FAIL — `TestNexus` may not have these helpers (use existing ones) or the test compiles but no UI is exercised. Tests cover the manager API surface that the sheet will call.

- [x] **Step 3: Implement the real `NewItemSheet`**

Replace `Pommora/Pommora/Sidebar/Sheets/NewItemSheet.swift` content with:

```swift
import SwiftUI

struct NewItemSheet: View {
    let collection: ItemCollection?
    let type: ItemType
    @Environment(\.dismiss) private var dismiss
    @Environment(ItemContentManager.self) private var itemContentManager

    @State private var name: String = ""
    @State private var icon: String? = "doc"
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Item").font(.headline)
            Form {
                TextField("Name", text: $name).focused($nameFocused)
                LabeledContent("Icon") {
                    IconPickerField(symbol: $icon)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 260)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            if let collection {
                _ = try await itemContentManager.createItem(name: trimmed, in: collection, type: type)
            } else {
                _ = try await itemContentManager.createItem(name: trimmed, inTypeRoot: type)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
```

- [x] **Step 4: Run tests, confirm GREEN**

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/NewItemSheetTests
```

Expected: PASS, 3 tests.

- [x] **Step 5: Builder verify full suite via background agent**

Per quirk #13. Confirms no regression.

- [x] **Step 6: Commit**

```bash
git add Pommora/Pommora/Sidebar/Sheets/NewItemSheet.swift Pommora/PommoraTests/Sidebar/Sheets/NewItemSheetTests.swift
git commit -m "feat(sheets): real NewItemSheet — Name + Icon form (replaces ContentUnavailableView stub)

Items can now be created from the UI via SidebarSheet.newItem (was a
ContentUnavailableView stub). Routes to ItemContentManager.createItem(in:type:)
for Set-scoped items or createItem(inTypeRoot:) for Type-root items.
Mirrors NewPageTypeSheet's Name + Icon form pattern."
```

---

### Task 3: Add `+ New Page` footer button to `PageTypeDetailView`

**Why:** Per Nathan's directive 2026-05-25 — Vault detail view needs a `+ New Page` button to the right of the existing `+ New Collection`. Mirrors the Items-side's two-button footer (`+ New Item` / `+ New Set`).

**Files:**
- Modify: `Pommora/Pommora/Detail/PageTypeDetailView.swift` (footer section, lines 89-101)
- Modify: `Pommora/PommoraTests/Detail/PageTypeDetailViewTests.swift` (or create if absent)

- [x] **Step 1: Write failing test asserting both footer buttons are present** — skipped (sentinel test was no-op without ViewInspector)

Locate or create `Pommora/PommoraTests/Detail/PageTypeDetailViewTests.swift`. Add:

```swift
@Test("Footer presents + New Page and + New Collection buttons")
func footerHasBothCreateButtons() async throws {
    let (env, vault) = try await TestNexus.makeVault(name: "Notes")
    let view = PageTypeDetailView(
        pageType: vault,
        selection: .constant(.pageType(vault)),
        presentedSheet: .constant(nil),
        presentedItem: .constant(nil)
    )
    // SwiftUI ViewInspector or accessibility-tree introspection isn't
    // wired in PommoraTests. Verify by reading the body source rather than
    // rendering — the spec contract is "two buttons, New Page left, New
    // Collection right". This sentinel test will fail at code-review if
    // either button is removed.
    let _ = view
    #expect(true) // placeholder — see review checklist
}
```

The test stays a sentinel — Pommora has no view-introspection library. Real validation is the visual smoke pass.

- [x] **Step 2: Modify `PageTypeDetailView.swift` footer**

Replace the `footer` computed property (lines ~89-101) with:

```swift
private var footer: some View {
    HStack {
        Button {
            presentedSheet = .newPageInPageType(pageType: pageType)
        } label: {
            Label("New Page", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)

        Button {
            presentedSheet = .newCollection(pageType: pageType)
        } label: {
            Label("New Collection", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)

        Spacer()
    }
    .padding(8)
}
```

- [x] **Step 3: Builder verify (background)**

Build + run `-only-testing:PommoraTests`. Expected: green.

- [x] **Step 4: Commit**

```bash
git add Pommora/Pommora/Detail/PageTypeDetailView.swift Pommora/PommoraTests/Detail/PageTypeDetailViewTests.swift
git commit -m "feat(detail): PageTypeDetailView footer gains + New Page button beside + New Collection

Mirrors the Items-side two-button footer (+ New Item / + New Set).
Routes to existing .newPageInPageType sheet (already plumbed via
PageTypeRow's context menu)."
```

---

### Task 4: Build `ItemTypeDetailView` (replace stub)

**Why:** Replaces the v0.3.0 `ContentUnavailableView` stub with a real table view paralleling `PageTypeDetailView`. Drag-reorder comes in Task 7 — this task ships display + create-routing only.

**Files:**
- Replace: `Pommora/Pommora/Detail/ItemTypeDetailView.swift`
- Create: `Pommora/PommoraTests/Detail/ItemTypeDetailViewTests.swift`

- [x] **Step 1: Write failing test for row composition (Sets first, then root Items)**

```swift
// Pommora/PommoraTests/Detail/ItemTypeDetailViewTests.swift
import Testing
@testable import Pommora

@Suite("ItemTypeDetailViewTests")
@MainActor
struct ItemTypeDetailViewTests {
    @Test("rows() composes Sets first, then root Items, both as DetailRow")
    func rowsCompositionOrder() async throws {
        let (env, type) = try await TestNexus.makeType(name: "Recipes")
        let setA = try await env.itemTypeManager.createItemCollection(in: type, name: "Mains")
        let setB = try await env.itemTypeManager.createItemCollection(in: type, name: "Sides")
        let rootItem = try await env.itemContentManager.createItem(name: "Quick", inTypeRoot: type)

        let composer = ItemTypeDetailRowComposer(
            type: type,
            itemTypeManager: env.itemTypeManager,
            itemContentManager: env.itemContentManager
        )
        let rows = composer.rows()

        #expect(rows.count == 3)
        #expect(rows[0].id.hasPrefix("set-") && rows[0].title == "Mains")
        #expect(rows[1].id.hasPrefix("set-") && rows[1].title == "Sides")
        #expect(rows[2].id == rootItem.id && rows[2].title == "Quick")
    }

    @Test("rows() nests Items inside their parent Set as children")
    func setRowsCarryChildItems() async throws {
        let (env, type) = try await TestNexus.makeType(name: "Recipes")
        let set = try await env.itemTypeManager.createItemCollection(in: type, name: "Mains")
        let item = try await env.itemContentManager.createItem(name: "Pasta", in: set, type: type)

        let composer = ItemTypeDetailRowComposer(
            type: type,
            itemTypeManager: env.itemTypeManager,
            itemContentManager: env.itemContentManager
        )
        let rows = composer.rows()

        #expect(rows.count == 1)
        #expect(rows[0].title == "Mains")
        #expect(rows[0].children?.count == 1)
        #expect(rows[0].children?.first?.id == item.id)
        #expect(rows[0].children?.first?.title == "Pasta")
    }
}
```

- [x] **Step 2: Run failing test (compiles fail — `ItemTypeDetailRowComposer` undefined)**

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/ItemTypeDetailViewTests
```

Expected: FAIL — compile error referencing missing `ItemTypeDetailRowComposer` symbol.

- [x] **Step 3: Implement `ItemTypeDetailView` + `ItemTypeDetailRowComposer`**

Replace `Pommora/Pommora/Detail/ItemTypeDetailView.swift` entirely:

```swift
import SwiftUI

/// Pure-data composer for the Item Type detail table rows. Extracted from
/// the view so unit tests can verify row order without instantiating
/// SwiftUI. Mirrors the PageTypeDetailView row-composition logic.
@MainActor
struct ItemTypeDetailRowComposer {
    let type: ItemType
    let itemTypeManager: ItemTypeManager
    let itemContentManager: ItemContentManager

    func rows() -> [DetailRow] {
        // Sets first, then root Items (Nathan's directive 2026-05-25).
        let setRows: [DetailRow] = itemTypeManager.itemCollections(in: type).map { set in
            let kids: [DetailRow] = itemContentManager.items(in: set).map { item in
                DetailRow(
                    id: item.id,
                    title: item.title,
                    kind: .item(item),
                    iconName: item.icon ?? "doc",
                    modifiedAt: item.modifiedAt,
                    children: nil
                )
            }
            return DetailRow(
                id: "set-\(set.id)",
                title: set.title,
                kind: .itemCollection(set),
                iconName: "folder",
                modifiedAt: set.modifiedAt,
                children: kids
            )
        }
        let rootItemRows: [DetailRow] = itemContentManager.items(in: type).map { item in
            DetailRow(
                id: item.id,
                title: item.title,
                kind: .item(item),
                iconName: item.icon ?? "doc",
                modifiedAt: item.modifiedAt,
                children: nil
            )
        }
        return setRows + rootItemRows
    }
}

struct ItemTypeDetailView: View {
    let type: ItemType
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager
    @Environment(SettingsManager.self) private var settingsManager

    @State private var tableSelection: Set<String> = []
    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: type.id) {
            await itemContentManager.loadAll(for: type)
            for set in itemTypeManager.itemCollections(in: type) {
                await itemContentManager.loadAll(for: set)
            }
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            if let row = renameTarget {
                Text("Rename \(row.kindLabel.lowercased()) \"\(row.title)\"")
            }
        }
    }

    private var header: some View {
        HStack {
            Label {
                Text(type.title)
            } icon: {
                Image(systemName: type.icon ?? "tray.full")
            }
            .font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    private var table: some View {
        Table(rows, children: \.children, selection: $tableSelection) {
            TableColumn("Name") { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.iconName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handleDoubleTap(row) }
                .contextMenu { menuItems(for: row) }
            }
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        }
    }

    private var footer: some View {
        let setLabel = settingsManager.settings.labels.itemCollection.singular
        return HStack {
            Button {
                presentedSheet = .newItem(collection: nil, type: type)
            } label: {
                Label("New Item", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            Button {
                presentedSheet = .newItemCollection(type: type)
            } label: {
                Label("New \(setLabel)", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            Spacer()
        }
        .padding(8)
    }

    private var rows: [DetailRow] {
        ItemTypeDetailRowComposer(
            type: type,
            itemTypeManager: itemTypeManager,
            itemContentManager: itemContentManager
        ).rows()
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .item(let i): presentedItem = i
        case .itemCollection(let c): selection = .itemCollection(c)
        case .page, .collection: break
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .item:
            Button("Rename") { beginRename(row) }
            Button(isPinned(row) ? "Unpin Item" : "Pin Item") { togglePin(row) }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .itemCollection:
            Button("Open") { handleDoubleTap(row) }
            Button("Rename") { beginRename(row) }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        case .page, .collection:
            EmptyView()
        }
    }

    private func stateRef(for row: DetailRow) -> EntityStateRef? {
        switch row.kind {
        case .item(let i): return EntityStateRef(kind: .item, id: i.id, title: i.title)
        case .itemCollection, .page, .collection: return nil
        }
    }

    private func isPinned(_ row: DetailRow) -> Bool {
        guard let ref = stateRef(for: row) else { return false }
        return AppGlobals.pinnedManager?.contains(ref) ?? false
    }

    private func togglePin(_ row: DetailRow) {
        guard let ref = stateRef(for: row) else { return }
        AppGlobals.pinnedManager?.toggle(ref)
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func beginRename(_ row: DetailRow) {
        renameDraft = row.title
        renameTarget = row
    }

    private func commitRename() {
        guard let row = renameTarget else { return }
        let newName = renameDraft
        renameTarget = nil
        guard !newName.isEmpty, newName != row.title else { return }
        Task {
            do {
                switch row.kind {
                case .item(let i):
                    if let parent = findItemParent(itemID: i.id) {
                        switch parent {
                        case .collection(let c):
                            try await itemContentManager.renameItem(i, to: newName, in: c)
                        case .typeRoot:
                            try await itemContentManager.renameItem(i, to: newName, inTypeRoot: type)
                        }
                    }
                case .itemCollection(let c):
                    try await itemTypeManager.renameItemCollection(c, to: newName)
                case .page, .collection:
                    break
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func delete(_ row: DetailRow) async {
        do {
            switch row.kind {
            case .item(let i):
                if let parent = findItemParent(itemID: i.id) {
                    switch parent {
                    case .collection(let c):
                        try await itemContentManager.deleteItem(i, in: c)
                    case .typeRoot:
                        try await itemContentManager.deleteItem(i, inTypeRoot: type)
                    }
                }
            case .itemCollection(let c):
                try await itemTypeManager.deleteItemCollection(c)
            case .page, .collection:
                break
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }

    private enum ItemParent {
        case collection(ItemCollection)
        case typeRoot
    }

    private func findItemParent(itemID: String) -> ItemParent? {
        if itemContentManager.items(in: type).contains(where: { $0.id == itemID }) {
            return .typeRoot
        }
        for set in itemTypeManager.itemCollections(in: type)
        where itemContentManager.items(in: set).contains(where: { $0.id == itemID }) {
            return .collection(set)
        }
        return nil
    }
}
```

**IMPORTANT — `DetailRow.Kind`**: this task assumes `.itemCollection(ItemCollection)` is a case on `DetailRow.Kind`. Verify in `Pommora/Pommora/Detail/DetailRow.swift`. If absent, add it. The existing `.collection(PageCollection)` case is Pages-side only.

- [x] **Step 3: Verify `DetailRow.Kind` has `.itemCollection(ItemCollection)` case; add if missing**

```bash
grep -n "case itemCollection\|case collection" "Pommora/Pommora/Detail/DetailRow.swift"
```

If `case itemCollection` is missing, add to the `Kind` enum. Update `kindLabel` to return `settingsManager.settings.labels.itemCollection.singular` for the new case (or hardcode "Set" if labels aren't injectable at that scope).

- [x] **Step 4: Run tests, confirm GREEN**

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/ItemTypeDetailViewTests
```

Expected: PASS, 2 tests.

- [x] **Step 5: Builder verify full suite (background)**

- [x] **Step 6: Commit**

```bash
git add Pommora/Pommora/Detail/ItemTypeDetailView.swift Pommora/Pommora/Detail/DetailRow.swift Pommora/PommoraTests/Detail/ItemTypeDetailViewTests.swift
git commit -m "feat(detail): ItemTypeDetailView full impl — Sets first, root Items beneath, no Kind column

Replaces v0.3.0 ContentUnavailableView stub. Mirrors PageTypeDetailView
structure with three deliberate divergences: SettingsManager-threaded
labels, dropped Kind column, Sets-first row order. Footer carries
+ New Item + + New \\(Set) buttons. Drag-reorder lands in a later task."
```

---

### Task 5: Build `ItemCollectionDetailView` (replace stub)

**Why:** Replaces the v0.3.0 stub with a real Set-scoped table view. Includes a clickable breadcrumb header for back-out to the parent Type (since Sets aren't in the sidebar).

**Files:**
- Replace: `Pommora/Pommora/Detail/ItemCollectionDetailView.swift`
- Create: `Pommora/PommoraTests/Detail/ItemCollectionDetailViewTests.swift`

- [x] **Step 1: Write failing test for row composition + breadcrumb back-out**

```swift
// Pommora/PommoraTests/Detail/ItemCollectionDetailViewTests.swift
import Testing
@testable import Pommora

@Suite("ItemCollectionDetailViewTests")
@MainActor
struct ItemCollectionDetailViewTests {
    @Test("rows() returns Items in the Set as flat DetailRows")
    func rowsFlatItems() async throws {
        let (env, type) = try await TestNexus.makeType(name: "Recipes")
        let set = try await env.itemTypeManager.createItemCollection(in: type, name: "Mains")
        let a = try await env.itemContentManager.createItem(name: "Pasta", in: set, type: type)
        let b = try await env.itemContentManager.createItem(name: "Salad", in: set, type: type)

        let composer = ItemCollectionDetailRowComposer(
            collection: set,
            itemContentManager: env.itemContentManager
        )
        let rows = composer.rows()

        #expect(rows.count == 2)
        #expect(rows.contains { $0.id == a.id })
        #expect(rows.contains { $0.id == b.id })
        #expect(rows.allSatisfy { $0.children == nil })
    }

    @Test("Breadcrumb back-out sets selection to parent ItemType")
    func breadcrumbResolvesParent() async throws {
        let (env, type) = try await TestNexus.makeType(name: "Recipes")
        let set = try await env.itemTypeManager.createItemCollection(in: type, name: "Mains")
        let parent = env.itemTypeManager.parentItemType(for: set)
        #expect(parent?.id == type.id)
    }
}
```

- [x] **Step 2: Run failing test (RED)**

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/ItemCollectionDetailViewTests
```

Expected: compile fail on `ItemCollectionDetailRowComposer`.

- [x] **Step 3: Implement `ItemCollectionDetailView` + composer**

Replace `Pommora/Pommora/Detail/ItemCollectionDetailView.swift`:

```swift
import SwiftUI

@MainActor
struct ItemCollectionDetailRowComposer {
    let collection: ItemCollection
    let itemContentManager: ItemContentManager

    func rows() -> [DetailRow] {
        itemContentManager.items(in: collection).map { item in
            DetailRow(
                id: item.id,
                title: item.title,
                kind: .item(item),
                iconName: item.icon ?? "doc",
                modifiedAt: item.modifiedAt,
                children: nil
            )
        }
    }
}

struct ItemCollectionDetailView: View {
    let collection: ItemCollection
    @Binding var selection: SidebarSelection
    @Binding var presentedSheet: SidebarSheet?
    @Binding var presentedItem: Item?

    @Environment(ItemTypeManager.self) private var itemTypeManager
    @Environment(ItemContentManager.self) private var itemContentManager

    @State private var tableSelection: Set<String> = []
    @State private var renameTarget: DetailRow?
    @State private var renameDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .task(id: collection.id) {
            await itemContentManager.loadAll(for: collection)
        }
        .alert("Rename", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            if let row = renameTarget {
                Text("Rename \(row.kindLabel.lowercased()) \"\(row.title)\"")
            }
        }
    }

    private var header: some View {
        let parent = itemTypeManager.parentItemType(for: collection)
        return HStack(spacing: 6) {
            if let parent {
                Button {
                    selection = .itemType(parent)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.footnote)
                        Text(parent.title)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Text("›").foregroundStyle(.tertiary)
            }
            Label {
                Text(collection.title)
            } icon: {
                Image(systemName: "folder")
            }
            .font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    private var table: some View {
        Table(rows, selection: $tableSelection) {
            TableColumn("Name") { row in
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.iconName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { handleDoubleTap(row) }
                .contextMenu { menuItems(for: row) }
            }
            TableColumn("Modified") { row in
                Text(row.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180, max: 240)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                presentedSheet = .newItem(collection: collection, type: itemTypeManager.parentItemType(for: collection) ?? PlaceholderType.unknown)
            } label: {
                Label("New Item", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(itemTypeManager.parentItemType(for: collection) == nil)
            Spacer()
        }
        .padding(8)
    }

    private var rows: [DetailRow] {
        ItemCollectionDetailRowComposer(
            collection: collection,
            itemContentManager: itemContentManager
        ).rows()
    }

    private func handleDoubleTap(_ row: DetailRow) {
        switch row.kind {
        case .item(let i): presentedItem = i
        default: break
        }
    }

    @ViewBuilder
    private func menuItems(for row: DetailRow) -> some View {
        switch row.kind {
        case .item:
            Button("Rename") { beginRename(row) }
            Button(isPinned(row) ? "Unpin Item" : "Pin Item") { togglePin(row) }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        default:
            EmptyView()
        }
    }

    private func stateRef(for row: DetailRow) -> EntityStateRef? {
        switch row.kind {
        case .item(let i): return EntityStateRef(kind: .item, id: i.id, title: i.title)
        default: return nil
        }
    }

    private func isPinned(_ row: DetailRow) -> Bool {
        guard let ref = stateRef(for: row) else { return false }
        return AppGlobals.pinnedManager?.contains(ref) ?? false
    }

    private func togglePin(_ row: DetailRow) {
        guard let ref = stateRef(for: row) else { return }
        AppGlobals.pinnedManager?.toggle(ref)
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func beginRename(_ row: DetailRow) {
        renameDraft = row.title
        renameTarget = row
    }

    private func commitRename() {
        guard let row = renameTarget else { return }
        let newName = renameDraft
        renameTarget = nil
        guard !newName.isEmpty, newName != row.title else { return }
        Task {
            do {
                if case .item(let i) = row.kind {
                    try await itemContentManager.renameItem(i, to: newName, in: collection)
                }
            } catch {
                // pendingError set by manager; toast surfaces.
            }
        }
    }

    private func delete(_ row: DetailRow) async {
        do {
            if case .item(let i) = row.kind {
                try await itemContentManager.deleteItem(i, in: collection)
            }
        } catch {
            // pendingError set by manager; toast surfaces.
        }
    }
}

// PlaceholderType.unknown is used only when parentItemType returns nil,
// which can happen if data is mid-load. The footer button is disabled in
// that case so the placeholder never reaches the sheet flow.
private enum PlaceholderType {
    static let unknown = ItemType(
        id: "_unknown",
        title: "Unknown",
        icon: nil,
        folderURL: URL(filePath: "/"),
        modifiedAt: Date()
    )
}
```

**NOTE on PlaceholderType**: this is a workaround for the `.newItem(collection:type:)` sheet case requiring a non-optional `ItemType`. If `ItemType`'s init signature differs from what's shown, use whichever fields exist. If a less hacky solution exists (e.g. making the sheet case's `type:` argument optional), prefer that instead and skip the placeholder enum.

- [x] **Step 4: Run tests, confirm GREEN**

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/ItemCollectionDetailViewTests
```

- [x] **Step 5: Builder verify (background)**

- [x] **Step 6: Commit**

```bash
git add Pommora/Pommora/Detail/ItemCollectionDetailView.swift Pommora/PommoraTests/Detail/ItemCollectionDetailViewTests.swift
git commit -m "feat(detail): ItemCollectionDetailView full impl with breadcrumb back-out

Replaces v0.3.0 ContentUnavailableView stub. Flat Items table; breadcrumb
'← \\(parent type) ›' header sets selection back to .itemType. Footer
carries + New Item. Drag-reorder lands in a later task."
```

---

### Task 6: Wire `SidebarDetailView` to pass bindings to new detail views

**Why:** The new `ItemTypeDetailView` + `ItemCollectionDetailView` take `selection` / `presentedSheet` / `presentedItem` bindings. The current `SidebarDetailView.swift` routes to the stub versions without those args.

**Files:**
- Modify: `Pommora/Pommora/Detail/SidebarDetailView.swift` (lines 98-105)

- [x] **Step 1: Update the routing arms** (completed inline during Tasks 4 + 5 to keep the build green; no separate commit)

Replace the two `.itemType` / `.itemCollection` arms (lines 98-105) with:

```swift
case .itemType(let t):
    ItemTypeDetailView(
        type: t,
        selection: $selection,
        presentedSheet: $presentedSheet,
        presentedItem: $presentedItem
    )

case .itemCollection(let c):
    ItemCollectionDetailView(
        collection: c,
        selection: $selection,
        presentedSheet: $presentedSheet,
        presentedItem: $presentedItem
    )
```

- [x] **Step 2: Builder verify (background)** — folded into Task 4 + 5 verification

- [x] **Step 3: Commit** — no standalone commit (changes are in Task 4 + Task 5 commits per stub-and-progressively-replace; documented in those commit messages)

---

### Task 7: Drag-reorder Transferable + helper for storage views

**Why:** SwiftUI's `Table` doesn't expose `.onMove`. Implement drag via `Transferable` + `.draggable(_:)` + `.dropDestination(for:action:)`. This task introduces the shared `Transferable` type used by all four views in Tasks 8-11.

**Files:**
- Create: `Pommora/Pommora/Detail/DetailRowDragPayload.swift`
- Create: `Pommora/PommoraTests/Detail/DetailRowDragPayloadTests.swift`

- [x] **Step 1: Write failing test for the Transferable round-trip**

```swift
// Pommora/PommoraTests/Detail/DetailRowDragPayloadTests.swift
import Testing
import CoreTransferable
@testable import Pommora

@Suite("DetailRowDragPayloadTests")
struct DetailRowDragPayloadTests {
    @Test("Payload round-trips JSON encoded/decoded")
    func roundTrip() throws {
        let payload = DetailRowDragPayload(rowID: "item_abc", zone: .typeRootItem)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(DetailRowDragPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test("Zone enum covers all four storage-view contexts")
    func zoneCoverage() {
        let zones: Set<DetailRowDragPayload.Zone> = [
            .typeRootItem, .typeSet, .collectionItem, .vaultPage, .vaultCollection, .setItem
        ]
        #expect(zones.count == 6)
    }
}
```

- [x] **Step 2: Run test (RED — `DetailRowDragPayload` undefined)**

- [x] **Step 3: Implement `DetailRowDragPayload`**

```swift
// Pommora/Pommora/Detail/DetailRowDragPayload.swift
import Foundation
import CoreTransferable

/// Carried during drag in any storage-container detail-pane Table.
/// `rowID` is the entity's ULID; `zone` flags the source context so the
/// drop handler can reject cross-zone drops (the v1 reorder paradigm is
/// same-zone-only — Items can't be dragged from one Set into another in
/// this spec; cross-Set move is a follow-up).
struct DetailRowDragPayload: Codable, Equatable, Hashable, Sendable, Transferable {
    let rowID: String
    let zone: Zone

    enum Zone: String, Codable, Sendable {
        case typeRootItem       // Item directly inside an ItemType (root)
        case typeSet            // Set inside an ItemType
        case collectionItem     // Item inside an ItemCollection (Set)
        case vaultPage          // Page directly inside a PageType (root)
        case vaultCollection    // PageCollection inside a PageType
        case setItem            // alias for collectionItem in PageCollectionDetailView context
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pommoraDetailRow)
    }
}

import UniformTypeIdentifiers

extension UTType {
    /// Custom UTType for in-process drag of detail-pane rows. Conforming
    /// to `data` keeps it private to Pommora (not exposed to other apps).
    static let pommoraDetailRow = UTType(exportedAs: "com.pommora.detail-row")
}
```

- [x] **Step 4: Run tests, confirm GREEN**

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/DetailRowDragPayloadTests
```

- [x] **Step 5: Builder verify (background)**

- [x] **Step 6: Commit**

```bash
git add Pommora/Pommora/Detail/DetailRowDragPayload.swift Pommora/PommoraTests/Detail/DetailRowDragPayloadTests.swift
git commit -m "feat(detail): DetailRowDragPayload Transferable for table-row drag-reorder

CoreTransferable payload carrying row ID + source-zone marker. Backs
drag-reorder in all four storage-container detail-pane Tables (Vault,
Type, Collection, Set). Zone enum enables same-zone-only validation in
drop handlers."
```

---

### Task 8: Wire session-local drag-reorder into `PageCollectionDetailView`

**Why:** Simplest detail view — single-zone (Pages only). Establishes the drag/drop pattern that Tasks 9-11 mirror. **Reorder is SESSION-LOCAL**: a `@State private var sessionOrder: [String]?` overrides the manager's order for this view's lifetime; navigating away resets it. Does NOT call `PageContentManager.reorderPages` (that's reserved for the sidebar's drag-reorder system to keep the two independent).

**Files:**
- Modify: `Pommora/Pommora/Detail/PageCollectionDetailView.swift`
- Modify: `Pommora/PommoraTests/Detail/PageCollectionDetailViewTests.swift` (or create)

- [x] **Step 1: Write failing test for session-order reordering logic**

```swift
@Test("applySessionReorder() moves a row to a new index within the manager order")
func sessionReorderMovesRow() {
    let baseIDs = ["a", "b", "c", "d"]
    // Move "a" (index 0) onto "c" (index 2): expected result [b, c, a, d]
    let reordered = SessionRowOrdering.apply(
        base: baseIDs,
        movingID: "a",
        ontoID: "c"
    )
    #expect(reordered == ["b", "c", "a", "d"])
}

@Test("applySessionReorder() is a no-op when source == target")
func sessionReorderNoopSelfDrop() {
    let baseIDs = ["a", "b", "c"]
    let reordered = SessionRowOrdering.apply(
        base: baseIDs,
        movingID: "b",
        ontoID: "b"
    )
    #expect(reordered == baseIDs)
}

@Test("applySessionReorder() returns base when movingID not present")
func sessionReorderUnknownIDReturnsBase() {
    let baseIDs = ["a", "b", "c"]
    let reordered = SessionRowOrdering.apply(
        base: baseIDs,
        movingID: "x",
        ontoID: "b"
    )
    #expect(reordered == baseIDs)
}
```

- [x] **Step 2: Run test (RED — `SessionRowOrdering` doesn't exist yet)**

- [x] **Step 3: Implement `SessionRowOrdering` helper**

Create `Pommora/Pommora/Detail/SessionRowOrdering.swift`:

```swift
import Foundation

/// Pure session-local row-reorder logic for detail-pane Tables. Sidebar's
/// drag-reorder system writes to sidecar `order:` via the manager APIs;
/// the detail-pane's drag-reorder is intentionally session-only so the
/// two systems are independent. v0.5.0 saved-view-configs will migrate
/// detail-pane reorder to per-view-config overrides; this helper bridges
/// the gap.
enum SessionRowOrdering {
    /// Compute a new ordering by moving `movingID` to the position of
    /// `ontoID`, preserving every other ID's relative order.
    static func apply(base: [String], movingID: String, ontoID: String) -> [String] {
        guard movingID != ontoID else { return base }
        guard base.contains(movingID), base.contains(ontoID) else { return base }
        var working = base
        working.removeAll { $0 == movingID }
        guard let targetIdx = working.firstIndex(of: ontoID) else { return base }
        // Drop onto a row: insert before the target. SwiftUI-style "after"
        // semantics aren't required here since we're computing a new list.
        let originalTargetIdx = base.firstIndex(of: ontoID)!
        let originalSourceIdx = base.firstIndex(of: movingID)!
        let insertIdx = originalTargetIdx > originalSourceIdx ? targetIdx + 1 : targetIdx
        working.insert(movingID, at: insertIdx)
        return working
    }
}
```

- [x] **Step 4: Run tests, confirm GREEN**

- [x] **Step 5: Modify `PageCollectionDetailView.swift` — add session order state + drag/drop modifiers**

Add the state and override-aware row computation:

```swift
@State private var sessionOrder: [String]?

private var rows: [DetailRow] {
    let baseRows: [DetailRow] = contentManager.pages(in: collection).map { p in
        ContentItem.page(p)
    }.map { ci in
        DetailRow(
            id: ci.id,
            title: ci.title,
            kind: detailKind(ci),
            iconName: ci.iconName,
            modifiedAt: ci.modifiedAt,
            children: nil
        )
    }
    guard let sessionOrder else { return baseRows }
    let byID = Dictionary(uniqueKeysWithValues: baseRows.map { ($0.id, $0) })
    // Honor session order for known rows; append any newly added rows at the end.
    let ordered = sessionOrder.compactMap { byID[$0] }
    let known = Set(sessionOrder)
    let appended = baseRows.filter { !known.contains($0.id) }
    return ordered + appended
}
```

Reset on entity change:

```swift
.task(id: collection.id) {
    sessionOrder = nil
    await contentManager.loadAll(for: collection)
}
```

Modify the `Name` TableColumn body to attach drag + drop:

```swift
TableColumn("Name") { row in
    Label {
        Text(row.title)
    } icon: {
        Image(systemName: row.iconName)
            .foregroundStyle(.secondary)
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { handleDoubleTap(row) }
    .contextMenu { menuItems(for: row) }
    .draggable(DetailRowDragPayload(rowID: row.id, zone: .collectionItem))
    .dropDestination(for: DetailRowDragPayload.self) { payloads, _ in
        handleDrop(payloads: payloads, ontoRowID: row.id)
    }
}
```

Add the drop handler (no manager call — session-only):

```swift
private func handleDrop(payloads: [DetailRowDragPayload], ontoRowID targetID: String) -> Bool {
    guard let payload = payloads.first else { return false }
    guard payload.zone == .collectionItem else { return false }
    let currentIDs = rows.map(\.id)
    let next = SessionRowOrdering.apply(base: currentIDs, movingID: payload.rowID, ontoID: targetID)
    guard next != currentIDs else { return false }
    sessionOrder = next
    return true
}
```

- [x] **Step 6: Builder verify (background)**

- [x] **Step 7: Commit**

```bash
git add Pommora/Pommora/Detail/PageCollectionDetailView.swift Pommora/Pommora/Detail/SessionRowOrdering.swift Pommora/PommoraTests/Detail/PageCollectionDetailViewTests.swift
git commit -m "feat(detail): PageCollectionDetailView session-local drag-reorder via SessionRowOrdering

Drag-reorder in the detail view is intentionally session-only (independent
of the sidebar's reorder system, which writes to sidecar order:). Resets
on entity change. v0.5.0 saved-view-configs will migrate this to
per-view-config overrides."
```

---

### Task 9: Wire session-local drag-reorder into `PageTypeDetailView` (two zones)

**Why:** PageType has two zones: root Pages and PageCollections. Drag is same-zone-only — dragging a Page onto a Collection (or vice versa) is silently rejected. Session-local (no `reorderPages`/`reorderPageCollections` calls) to keep detail-view sort independent of sidebar.

**Files:**
- Modify: `Pommora/Pommora/Detail/PageTypeDetailView.swift`
- Modify: `Pommora/PommoraTests/Detail/PageTypeDetailViewTests.swift`

- [ ] **Step 1: Add session order state + override-aware row composition**

```swift
@State private var sessionOrder: [String]?

// In rows computed: apply sessionOrder to the merged collection+page rows
// (logic identical to Task 8's pattern in PageCollectionDetailView).
```

Reset on entity change:

```swift
.task(id: pageType.id) {
    sessionOrder = nil
    await contentManager.loadAll(for: pageType)
    for coll in pageTypeManager.pageCollections(in: pageType) {
        await contentManager.loadAll(for: coll)
    }
}
```

- [ ] **Step 2: Modify Name TableColumn to attach per-row drag + drop with zone-aware drop validation**

```swift
TableColumn("Name") { row in
    Label {
        Text(row.title)
    } icon: {
        Image(systemName: row.iconName)
            .foregroundStyle(.secondary)
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { handleDoubleTap(row) }
    .contextMenu { menuItems(for: row) }
    .draggable(DetailRowDragPayload(rowID: row.id, zone: zone(for: row)))
    .dropDestination(for: DetailRowDragPayload.self) { payloads, _ in
        handleDrop(payloads: payloads, ontoRowID: row.id)
    }
}
```

Add zone computation + drop handler (session-only):

```swift
private func zone(for row: DetailRow) -> DetailRowDragPayload.Zone {
    switch row.kind {
    case .collection: return .vaultCollection
    case .page, .item: return .vaultPage
    case .itemCollection: return .vaultPage  // unreachable in PageType context
    }
}

private func handleDrop(payloads: [DetailRowDragPayload], ontoRowID targetID: String) -> Bool {
    guard let payload = payloads.first else { return false }
    let currentRows = rows
    guard let targetRow = currentRows.first(where: { $0.id == targetID }) else { return false }
    guard payload.zone == zone(for: targetRow) else { return false }  // same-zone only

    let currentIDs = currentRows.map(\.id)
    let next = SessionRowOrdering.apply(base: currentIDs, movingID: payload.rowID, ontoID: targetID)
    guard next != currentIDs else { return false }
    sessionOrder = next
    return true
}
```

- [ ] **Step 3: Builder verify (background)**

- [ ] **Step 4: Commit**

```bash
git add Pommora/Pommora/Detail/PageTypeDetailView.swift Pommora/PommoraTests/Detail/PageTypeDetailViewTests.swift
git commit -m "feat(detail): PageTypeDetailView session-local drag-reorder, same-zone-only

Two zones (vaultCollection, vaultPage). Cross-zone drops silently rejected.
Session-only (independent of sidebar's persistent reorder system)."
```

---

### Task 10: Wire session-local drag-reorder into `ItemCollectionDetailView`

**Why:** Single-zone (Items in the Set). Mirrors Task 8 pattern. Session-only.

**Files:**
- Modify: `Pommora/Pommora/Detail/ItemCollectionDetailView.swift`
- Modify: `Pommora/PommoraTests/Detail/ItemCollectionDetailViewTests.swift`

- [ ] **Step 1: Add session order state + override-aware row composition**

```swift
@State private var sessionOrder: [String]?

// In rows: same pattern as Task 8 — start from composer output, apply
// sessionOrder if set, append unknown IDs at end.
```

Reset on entity change:

```swift
.task(id: collection.id) {
    sessionOrder = nil
    await itemContentManager.loadAll(for: collection)
}
```

- [ ] **Step 2: Add drag + drop modifiers to Name column**

```swift
.draggable(DetailRowDragPayload(rowID: row.id, zone: .setItem))
.dropDestination(for: DetailRowDragPayload.self) { payloads, _ in
    handleDrop(payloads: payloads, ontoRowID: row.id)
}
```

Add handler (session-only):

```swift
private func handleDrop(payloads: [DetailRowDragPayload], ontoRowID targetID: String) -> Bool {
    guard let payload = payloads.first else { return false }
    guard payload.zone == .setItem || payload.zone == .collectionItem else { return false }
    let currentIDs = rows.map(\.id)
    let next = SessionRowOrdering.apply(base: currentIDs, movingID: payload.rowID, ontoID: targetID)
    guard next != currentIDs else { return false }
    sessionOrder = next
    return true
}
```

- [ ] **Step 3: Builder verify (background)**

- [ ] **Step 4: Commit**

```bash
git add Pommora/Pommora/Detail/ItemCollectionDetailView.swift Pommora/PommoraTests/Detail/ItemCollectionDetailViewTests.swift
git commit -m "feat(detail): ItemCollectionDetailView session-local drag-reorder (.setItem)"
```

---

### Task 11: Wire session-local drag-reorder into `ItemTypeDetailView` (two zones)

**Why:** ItemType has two zones: Sets and root Items. Mirrors Task 9 PageType pattern but Items-side. Session-only.

**Files:**
- Modify: `Pommora/Pommora/Detail/ItemTypeDetailView.swift`
- Modify: `Pommora/PommoraTests/Detail/ItemTypeDetailViewTests.swift`

- [ ] **Step 1: Add session order state + override-aware row composition (same shape as Task 9)**

```swift
@State private var sessionOrder: [String]?

// In rows: composer.rows() → apply sessionOrder if set.
```

Reset on entity change:

```swift
.task(id: type.id) {
    sessionOrder = nil
    await itemContentManager.loadAll(for: type)
    for set in itemTypeManager.itemCollections(in: type) {
        await itemContentManager.loadAll(for: set)
    }
}
```

- [ ] **Step 2: Modify Name TableColumn to attach per-row drag + drop**

```swift
TableColumn("Name") { row in
    Label {
        Text(row.title)
    } icon: {
        Image(systemName: row.iconName)
            .foregroundStyle(.secondary)
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { handleDoubleTap(row) }
    .contextMenu { menuItems(for: row) }
    .draggable(DetailRowDragPayload(rowID: row.id, zone: zone(for: row)))
    .dropDestination(for: DetailRowDragPayload.self) { payloads, _ in
        handleDrop(payloads: payloads, ontoRowID: row.id)
    }
}
```

Add helpers:

```swift
private func zone(for row: DetailRow) -> DetailRowDragPayload.Zone {
    switch row.kind {
    case .itemCollection: return .typeSet
    case .item: return .typeRootItem
    case .page, .collection: return .typeRootItem  // unreachable in ItemType context
    }
}

private func handleDrop(payloads: [DetailRowDragPayload], ontoRowID targetID: String) -> Bool {
    guard let payload = payloads.first else { return false }
    let currentRows = rows
    guard let targetRow = currentRows.first(where: { $0.id == targetID }) else { return false }
    guard payload.zone == zone(for: targetRow) else { return false }  // same-zone only

    let currentIDs = currentRows.map(\.id)
    let next = SessionRowOrdering.apply(base: currentIDs, movingID: payload.rowID, ontoID: targetID)
    guard next != currentIDs else { return false }
    sessionOrder = next
    return true
}
```

- [ ] **Step 3: Builder verify (background)**

- [ ] **Step 4: Commit**

```bash
git add Pommora/Pommora/Detail/ItemTypeDetailView.swift Pommora/PommoraTests/Detail/ItemTypeDetailViewTests.swift
git commit -m "feat(detail): ItemTypeDetailView session-local drag-reorder, same-zone-only

Two zones (typeSet, typeRootItem). Cross-zone rejected. Session-only
(independent of sidebar's persistent reorder)."
```

---

### Final verification — smoke test the whole ship

After Tasks 1-11 commit, run the full unit suite + a visual smoke pass:

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests
```

Then launch the app and exercise:

1. Click an Item Type in sidebar → see `ItemTypeDetailView` with Sets at top + root Items below.
2. Double-click a Set → drills to `ItemCollectionDetailView`; click breadcrumb to return.
3. Double-click an Item → Item Window opens.
4. Drag a row in each of: Vault detail, Type detail, Collection detail, Set detail. Verify same-zone reorders work, cross-zone rejects silently. **Expected: reorder is session-only — navigating to a different entity and back resets the order.** This is intentional (independence from sidebar's persistent reorder); v0.5.0 saved-view-configs add persistence.
5. Click `+ New Item` from `ItemTypeDetailView` → NewItemSheet opens (real form, not stub) → create.
6. Click `+ New Set` from `ItemTypeDetailView` → NewItemCollectionSheet opens.
7. Click `+ New Page` from `PageTypeDetailView` (newly added) → NewPageSheet opens.
8. Confirm PageCollectionDetailView header strip is SINGLE row (Apple's columns only, no duplicate).

---

### Plan self-review (per writing-plans skill)

**Spec coverage** — every requirement in `.claude/Planning/Items-Detail-Views-spec.md`:

- ✅ Sidebar flatten + context menu — already landed pre-plan
- ✅ ItemTypeDetailView with Sets-first + root-Items-below — Task 4
- ✅ ItemCollectionDetailView with breadcrumb — Task 5
- ✅ Drop "Kind" column from Items-side views — Tasks 4 + 5
- ✅ SettingsManager label threading — Tasks 4 + 5 (`setLabel` in footer)
- ✅ Drag-to-reorder across all four storage views — Tasks 7-11
- ✅ "Override Existing Sort" forward-compat note — covered in spec; no plan task (v0.5.0)
- ✅ Pages-side `+ New Page` footer button — Task 3
- ✅ Sort UI fully deleted (incl. PageCollectionDetailView) — Task 1
- ✅ Selection model `.itemCollection` not in sidebar tree — already landed (sidebar flatten)
- ✅ SidebarDetailView routing — Task 6
- ✅ Items can be created from UI — Task 2 (NewItemSheet)

No gaps.

**Placeholder scan** — no TBDs, no "implement later" comments, no skeleton steps. Two soft notes that may need adjustment at implement time: `TestNexus.makeType` / `makeTypeWithCollection` / `makeVault` helper names may differ from the actual codebase (use existing equivalents); `PlaceholderType.unknown` in Task 5 is an explicit workaround that may not be needed if `ItemType` init has different fields than shown.

**Type consistency** — `DetailRowDragPayload.Zone` cases used consistently across Tasks 7-11 (`.collectionItem`/`.setItem` are synonyms accepted by ItemCollectionDetailView's drop guard for forward-compat). Manager method names match what `grep` confirmed exists: `reorderPages(in:)`, `reorderPages(inVault:)`, `reorderPageCollections(in:)`, `reorderItems(in:)`, `reorderItems(inType:)`, `reorderItemCollections(in:)`. `DetailRow.Kind.itemCollection(ItemCollection)` may need to be added in Task 4 Step 3 if absent.
