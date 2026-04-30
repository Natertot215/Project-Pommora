# Lessons — Pommora

One lesson per failure pattern. Never make the same mistake twice. Each entry includes the mistake, why it's wrong, the rule going forward, and the incident(s) that proved it.

---

## L-001 · Don't hand-tune UI dimensions — use SwiftUI semantic primitives

**Applies before:** any UI change — sizing, fonts, icon scale, padding, row heights, color, materials, drag/drop, animations.

**The mistake:** Reaching for hand-coded dimensions instead of SwiftUI's semantic modifiers:
- `.frame(width: 22)` on an Image to "make the icon bigger"
- `.font(.system(size: 13))` to size a label
- `.font(.title3)` applied directly to an icon (instead of letting `Label` + `.imageScale` handle it)
- Hand-rolled `HStack { Image; Text }` instead of `Label`
- Manual row paddings to fake `.controlSize(.regular)` behavior
- Nested `ScrollView` hacks instead of `.listSectionSeparator(.hidden)`
- Manual width math on title vs. detail instead of `.layoutPriority` + `.lineLimit().truncationMode(.tail)`
- Hand-rolled `RoundedRectangle` selection highlights instead of letting `List`/`.tag` handle selection

**Why it's wrong:** Apple's semantic modifiers automatically scale with `.controlSize`, the system Sidebar size setting (System Settings → Appearance), and Dynamic Type. Hand-tuned literals silently break all three — the app looks fine on my machine and wrong on every other machine. Nathan's framing: *"making up what I don't know about design principles."*

**The rule:**

| Want this | Use this | Don't do this |
|---|---|---|
| Bigger icon in a row | `.imageScale(.large)` on the `Label`/`List` | `.frame(width: 22)` on `Image` |
| Bigger icon + text together | `Label` + `.font(.headline)` + `.imageScale(.large)` | `.font(.system(size: 16))` or `.font(.title3)` on icon |
| Sidebar size variants | `.controlSize(.small/.regular/.large)` (per HIG Sidebars) | hand-tuned row paddings |
| Hide section dividers in a `List` | `.listSectionSeparator(.hidden)` | nested `ScrollView` hacks |
| Detail wins over title in a row | `.layoutPriority(1)` on detail + `.lineLimit(1).truncationMode(.tail)` on title | manual width math |
| Selection highlight in a row | `List` + `.tag(...)` selection | `RoundedRectangle.fill(Color.accentColor)` + `onTapGesture` |
| Color | `Color.accentColor`, `.primary`, `.secondary`, `Color(nsColor: .systemX)` | hex literals from Figma |
| Material backgrounds | `.regularMaterial`, `.thinMaterial`, etc. | hand-mixed RGBA |

**Verification protocol before writing the code:**
1. Identify the exact SwiftUI primitive you'll use. Name it out loud.
2. Confirm it exists and behaves as you think — see L-002.
3. If matching a screenshot from Finder/Mail/Notes/Photos/Settings/Xcode, name the primitive that produces that look. The screenshot is source of truth; your job is to map it to the primitive.
4. If HIG doesn't specify exact dimensions for what you're building, **say so explicitly** to Nathan and ask. Don't pick a number.

**Incidents:**
- **2026-04-26** — Initial occurrence. Sidebar work introduced `.frame(width: 22)` on icons and `.font(.title3)` on a Label-replacement `HStack`. Nathan flagged it. Rewrote with `Label` + `.imageScale(.large)` + `.controlSize(.regular)`.
- **2026-04-28** — Orphan-row overflow branch (`SidebarView.orphanRow`, lines 207–231 pre-fix). When `orphanFiles.count > 25`, a separate `ScrollView + LazyVStack` path was rendered with hand-rolled selection: `RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.85))` background, `.padding(.horizontal, 8).padding(.vertical, 4)`, `Color.white` foreground, `onTapGesture` bypassing `List`'s `.tag` selection, plus a hardcoded `CGFloat = 26` estimated row height. Scrapped-feature artifact. Fix: delete the overflow branch entirely; render all orphans in the normal `ForEach` path so `List` scrolls and handles selection.
- **2026-04-28** — `LibrarySearch.run` silently excluded orphan files. Two file code paths (folder-resident vs orphan) must receive identical treatment unless there is an explicit, documented reason to differ. See L-004.

---

## L-002 · Verify SwiftUI APIs against the source — never invent from memory

**Applies before:** introducing or modifying any SwiftUI modifier, initializer, type, or protocol conformance.

**The mistake:** Writing SwiftUI code based on what the API "probably" looks like, then having it fail to compile or — worse — compile but behave wrong because:
- The modifier doesn't exist on macOS 26 (or never existed at all)
- The signature has different parameter labels than remembered
- A required associated type, generic constraint, or `@available` annotation is missing
- The modifier exists but does something subtly different than assumed

Apple docs are JS-rendered and frequently fail to fetch. Training data has gaps across SwiftUI versions. Memory is unreliable for API surface.

**The rule — source-of-truth hierarchy:**
1. SwiftUI `.swiftinterface` in the macOS 26 SDK: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface` — use `grep -n` for exact signatures, generics, defaults, and `@available` annotations.
   ```bash
   grep -n "func draggable" /Applications/Xcode.app/.../arm64e-apple-macos.swiftinterface
   ```
2. Apple SwiftUI docs — narrative explanation; often unreachable, fall back to (1).
3. Apple HIG — for visual correctness (sidebar widths, list row sizes, materials).
4. Shipped macOS apps (Finder, Mail, Notes, Photos, Settings, Xcode) — when HIG doesn't pixel-spec something, the canonical apps are the reference.

**Verification protocol:**
1. Name the modifier/type you're about to use.
2. Grep the `.swiftinterface` (or open Apple docs) and confirm: it exists, the signature matches, it's available on macOS 26 (no `@available(macOS, deprecated:)` past our floor).
3. If the source is unreachable, **say so to Nathan**. Don't guess.
4. In the code change description, cite where you verified — file + line, or URL.

"I think this is how it works" is not acceptable.

**Incidents:**
- **2026-04-28 — Drag-reorder rewrite spiral (4 rejected iterations).** Root cause: `.listStyle(.sidebar)` delegates to `NSOutlineView`, which forces the legacy blue insertion bar regardless of which SwiftUI drag modifiers are applied. The macOS 26 container-drag API (`dragContainer`, `draggable(_:id:containerNamespace:)`) only works under `.listStyle(.inset)` or `.listStyle(.plain)`. Never verified against the swiftinterface before starting. 4 iterations wasted.

---

## L-003 · NavigationSplitView — always use `.prominentDetail` for independent columns

**Applies before:** any change to `NavigationSplitView` layout, column widths, or split-view style.

**The mistake:** Leaving `NavigationSplitView` at its default `.balanced` style when the design intent is independent column resizing. The default distributes available width proportionally — dragging the sidebar divider causes the middle column to shrink/grow to compensate.

In a three-column layout the user expects:
- Dragging the sidebar divider → only the editor (detail) absorbs the change
- Dragging the content divider → only the editor absorbs the change
- Middle column width is not coupled to sidebar width

`.balanced` violates this. Nathan's framing: *"adjusting the sidebar should not impact the other bars."*

**The rule:** Add `.navigationSplitViewStyle(.prominentDetail)`. The detail (editor) column becomes the flexible absorber. All new `NavigationSplitView` instances in Pommora must have this.

```swift
NavigationSplitView { ... } content: { ... } detail: { ... }
    .navigationSplitViewStyle(.prominentDetail)
```

Verify: `grep -n "prominentDetail" …arm64e-apple-macos.swiftinterface` → `ProminentDetailNavigationSplitViewStyle`, available macOS 13+.

**Incidents:**
- **2026-04-28** — Walking skeleton shipped with default `.balanced`. Nathan: "adjusting the sidebar adjusts the other [column]." Fixed in `ContentView.swift` by adding `.navigationSplitViewStyle(.prominentDetail)`.

---

## L-004 · Orphan files are first-class — handle identically to folder files

**Applies before:** any code path that touches files: search, display, selection, actions, indexing.

**The mistake:** Silently excluding or special-casing orphan files (`folder == nil`) in paths that handle folder-resident files.

**The rule:** Every file code path must explicitly handle `file.folder == nil` with identical logic. If there's a separate orphan branch, justify it or delete it.

**Incidents:**
- **2026-04-28** — `LibrarySearch.run` only iterated `folder.files` — orphans silently excluded from search. Fixed by extending `run(query:folders:orphanFiles:cache:)` to iterate orphans.

---

## L-005 · Pin DerivedData before behavioral debugging

**Applies before:** debugging any unexpected app behavior.

**The mistake:** Building to one DerivedData hash while the running app came from a different build. Changes are invisible in the running binary.

**The rule:** Before debugging: `ls ~/Library/Developer/Xcode/DerivedData/ | grep Pommora`. Confirm exactly one entry. Pin: `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx`.

**Incidents:**
- **2026-04-28** — `xcodebuild` wrote to `Pommora-fytgnsxnxwozlabwmanlcscyocuv` while the running app was `Pommora-auqxmapnajdwrzeypbqojwmlerkx`. Multiple debug rounds wasted. Nathan caught it.

---

## L-006 · Surface architectural constraints before writing code, not after four failures

**Applies before:** any drag/drop, animation, layout rewrite, or complex interaction feature.

**The mistake:** Attempting multiple implementations of a feature blocked by an architectural constraint, without surfacing the constraint first.

**The rule:** Before any complex feature, identify the constraint. If SwiftUI can't achieve it natively in the current architecture, say so before writing code. After the second rejection of the same feature: stop and explain the architectural constraint before attempting anything else.

**Incidents:**
- **2026-04-28** — Finder-style displacement drag rejected 4 times. Constraint (`.listStyle(.sidebar)` → `NSOutlineView`) was never surfaced upfront.
