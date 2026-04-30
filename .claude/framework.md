# Framework — PommoraUI

The single source for **what this skeleton is, what it provides, and what's locked**. Read before planning any feature, scoping work, or making architectural decisions. The code answers *how*; this file answers *what* and *why*.

---

## Vision

A generic native macOS app skeleton built against the macOS 26 design language. The skeleton provides a verified three-column `NavigationSplitView` shell, a `.searchable` sidebar, a placeholder middle column, and a curated `Components/` library of swiftinterface-verified SwiftUI primitives. Future features are added incrementally on top of this foundation.

This branch (`PommoraUI`) is **infrastructure**, not a product. It deliberately has no domain features.

---

## Skeleton scope

What's shipped in the skeleton:

- Three-column `NavigationSplitView` with `.navigationSplitViewStyle(.prominentDetail)` — sidebar and middle column resize independently; the detail (right) column absorbs all width changes.
- Sidebar with a single placeholder `Favorites` section and the `.searchable(placement: .sidebar)` scaffold (search field renders; no targets to search yet).
- Middle column shows a `ContentUnavailableView` placeholder when nothing is selected.
- No `ModelContainer` attached to the app yet. SwiftData is **not** imported in `PommoraApp.swift`. When the first feature needs persistence, import `SwiftData`, declare an `@Model` type, and add `.modelContainer(for: <YourModel>.self)` to the `WindowGroup`. **Do not** scaffold a `.modelContainer(for: [])` empty container — see L-007.
- `Components/` directory containing one file per primitive category, each with verified SwiftUI examples and `#Preview` blocks.

Hard constraints (carried over from Pommora; transcend the re-scope):

- No AppKit wraps — `NSViewRepresentable` is off the table ("swift ONLY items").
- No third-party UI libraries.
- macOS 26 only — no backward compat.
- No auto-save logic, no file IO scaffold (none needed without a feature).

---

## Component categories

The `Components/` directory is organized by SwiftUI primitive category. Each file contains small, verified, swiftinterface-cited examples with `#Preview` blocks.

| Category | File | Includes |
|---|---|---|
| Layout | `LayoutComponents.swift` | `VStack`, `HStack`, `ZStack`, `Spacer`, `Divider` |
| Text | `TextComponents.swift` | `Text`, `Label`, `TextField` |
| Controls | `ControlComponents.swift` | `Button` (all styles), `Toggle` |
| Lists | `ListComponents.swift` | `List`, `ForEach`, `Section`, `Table` |
| Navigation | `NavigationComponents.swift` | `NavigationStack`, `NavigationSplitView`, `NavigationLink`, `TabView` |

Adding a new category: create a new file in `Components/`, add a row to this table, add a section in `.claude/components-reference.md`. Every example must be cited against the macOS 26 swiftinterface per `swift-uix-rules.md`.

---

## Standing constraints

These are non-obvious facts that don't surface from reading the code or git history.

- **No AppKit in skeleton.** Nathan explicitly: "swift ONLY items." `NSViewRepresentable` is off the table.
- **`PBXFileSystemSynchronizedRootGroup`.** New `.swift` files in `Pommora/Pommora/` compile automatically — no `project.pbxproj` edit needed.
- **DerivedData hash to pin.** `Pommora-auqxmapnajdwrzeypbqojwmlerkx`. Always pin with `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx` when running `xcodebuild`. See L-005 in `lessons.md`.
- **Bundle identifier kept as `com.nathantaichman.Pommora`.** Branch name is `PommoraUI` but the Xcode target, scheme, and bundle ID stay `Pommora`. No rename needed.
- **`main` is Pommora-the-markdown-editor.** PommoraUI is a fork. Don't merge product features back into `main` without explicit direction.

---

## Deferred / locked decisions

1. **No features in the skeleton.** Features are added in subsequent sessions, one at a time, on top of this foundation.
2. **No `Settings` scene yet.** Add when the first feature requires user-configurable state.
3. **No `AppState` global model yet.** Add when feature state needs sharing across columns.
4. **Search field has no targets.** The `.searchable` modifier renders, but the binding doesn't filter anything until a feature provides a list.
5. **Middle column is `ContentUnavailableView` only.** Replaced by feature-owned content when the first feature lands.
6. **Components library is curated, not exhaustive.** Five categories at skeleton time. New categories added on demand and recorded in this file's table.

---

## Planning checklist

Run before scoping any task.

- [ ] Does this require AppKit? It's out of scope. Surface to Nathan.
- [ ] Does this add or change a `NavigationSplitView`? Must use `.prominentDetail`. (L-003)
- [ ] Does this introduce a SwiftUI component or modifier? Check `components-reference.md` first; verify against the swiftinterface per `swift-uix-rules.md`. (L-002)
- [ ] Does this introduce shared state? Decide on `@Observable` model vs `@AppStorage` vs SwiftData; document the choice in this file's "Standing constraints" if non-obvious.
- [ ] Does this register a SwiftData model? Update `PommoraApp.modelContainer` schema and add the `@Model` type under a domain-named subdirectory (not `Models/` — that name was deleted with the editor).
