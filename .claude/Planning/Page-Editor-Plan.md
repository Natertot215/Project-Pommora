### Plan: v0.2.7.2 — Page editor fixes (Blockquote + Tables)

> **HR / divider scope deliberately scrubbed (Session 12 follow-up, 2026-05-20):** the original three-feature plan included an HR rendering pass that was attempted and reverted. The replacement HR approach will be developed as a separate plan; this document now covers Blockquote + Tables only.

> **This file supersedes the prior "Page Editor — Options Inventory" contents** (the Option 1 / Option 2 / Option 3 catalog used during v0.2.7 prep). That decision shipped as `v0.2.7.0` (vendored `swift-markdown-engine` as local SPM + Apple `swift-markdown 0.8.0`). The historical inventory lives in git history if needed — this doc is now the active plan for the next patch.

#### Context

Session 9 shipped `v0.2.7.0` — the native TextKit 2 Page editor — but two Apple-Notes-style features Nathan flagged remain broken or missing (HR was a third item in the original plan; see scrub note above):

1. **Blockquotes (`>`)** — render with NSAttributedString `.backgroundColor` only (glyph-rect, NOT full paragraph) + a paragraphStyle headIndent. Result: weak visual treatment, no accent bar, bg only covers glyph rects.
2. **Tables** — currently `AppleASTSupplementalStyler.visitTable` hides pipes + separator row and applies monospace + faint bg tint. Result: monospaced text, not a real grid. Nathan locked: real-looking grid, per-cell editing, drag-resize on the inline view, widths persist on the page (frontmatter), markdown on disk stays standard GFM (no width round-trip needed).

**Research basis — four rounds total.**

Rounds 1–3 cloned 11 reference repos: MarkdownView, swift-markdown-ui, MarkdownKit, STTextView, Down, MacDown, CommonMarkAttributedString, Textual, Apple swift-markdown, Pommora's vendored swift-markdown-engine upstream, Apple's `EnrichingYourTextInTextViews` TextKit 2 sample.

Round 4 stress-tested the prior plan with three parallel agents:
- **Agent A (Apple-native visual specs)** pinned each value to an Apple-source citation; flagged the `NSColor.separatorColor.withAlphaComponent(0.8)` double-attenuation as the root cause of the "weak" blockquote treatment Nathan reported.
- **Agent B (ecosystem scan, late 2025 / early 2026)** confirmed nothing new has shipped that simplifies inline editing — iOS 26 `TextEditor` doesn't admit attachments; Apple Notes' own markdown round-trip fails on tables; STTextView stalled (Krzyzanowski's Aug 2025 "TextKit 2: The Promised Land" essay catalogs unfixed bugs). Verdict: no shortcuts available for fully-inline; the simpler popover-edit path is the meaningful lever.
- **Agent C (stress-test for over-engineering)** found that the prior plan's 6-stage attachment+substitution model exists solely to satisfy fully-inline cell editing. A read-only inline grid + double-click popover hits the same Apple-Notes visual at ~1/3 the cost and eliminates 4 of the 7 risks.

**User decisions from Round 4:**
- Tables → **Option A**: read-only inline grid + double-click popover for cell editing + inline drag-resize column dividers + frontmatter width persistence.
- Blockquote → **Apple Notes parity**: vertical bar + indent, no background tint.

#### Architecture decisions (locked from Round 4)

| Element | Decision | Why |
|---|---|---|
| Blockquote rendering | Custom `drawBlockquote` — rounded-rect grey card (6pt corner radius) + 3pt vertical accent bar INSIDE the card (raw `NSColor.separatorColor`), `paragraphStyle.headIndent = 20`. Card spans full line-fragment width minus textInsets. Multi-line blockquotes use per-fragment corner-rounding (first/middle/last/only detection via `BlockquoteMetadata.sourceRange` attribute payload) to render as ONE visually contiguous card. NO nested support in v1. | Apple Calendar event-card chrome (Round 6 — Nathan-flagged with screenshot; supersedes the prior Apple Notes minimal-bar target). Mirrors `drawCodeBlockBackground`'s CGPath + bg-fill pattern at body-text scale. |
| Blockquote bg tint | `Color.primary.opacity(0.06)` (resolved as `NSColor.labelColor.withAlphaComponent(0.06)` for AppKit draw) with 6pt corner radius | Round 6 — visual reference: Apple Calendar Today widget event cards. Subtle in dark mode, equally subtle in light. |
| **Table inline render** | **Core Graphics grid overlay drawn in `MarkdownTextLayoutFragment.draw`. Markdown source remains in text storage as `\| Cell \|`. No NSTextAttachment, no NSHostingView, no substitution machinery. No `NSTextTable` either — Apple's own TextEdit silently downgrades to TextKit 1 when a table is inserted; Apple Notes never adopted it.** | Round 4 Agent C: 6-stage attachment model exists solely for fully-inline editing. Nathan chose popover-edit → ~6h saved + 4 risks eliminated. Files truly canonical. Round 5 (this session) re-tested the Apple-native option: `NSTextTable`/`NSTextBlock` exist since OS X 10.3 but were never promoted to TextKit 2 (Krzyzanowski Aug 2025 "TextKit 2: The Promised Land" — TextEdit downgrade is the smoking gun; Apple Notes uses a custom protobuf document model, not the AppKit text system). Adopting NSTextTable would forfeit the TextKit-2-native Writing Tools / Look Up / dynamic-color wins from Session 9. Core Graphics overlay IS the 2026 Apple-native path. |
| Table source text in storage | Apply low-opacity color + slightly muted font on pipes/dashes via attribute so source visually recedes under the grid overlay (still selectable, still in storage) | Keep text in storage for Find/Replace + canonical body + edit-by-typing for power users who want to edit raw markdown by clicking past the grid. |
| Table column auto-sizing | Auto-size from content by default; user drag-resize overrides | Apple Notes default; SwiftUI Grid behavior. |
| Table drag-resize | Inline drag column dividers (cursor changes to `.resizeLeftRight`; click-drag → live update). Same drag supported in popover. | Nathan-requested; in scope for v0.2.7.2. |
| Table widths persistence | Pommora frontmatter extension `pommora_table_widths` indexed by table position + column-count fingerprint | Markdown spec doesn't carry widths; frontmatter survives reload; Pommora-namespaced. |
| **Table cell editing** | Double-click any cell → SwiftUI popover (NSPopover hosting NSHostingView<PommoraTablePopover>) anchored to table rect. Popover contains identical styled Grid + editable TextField cells + drag-resize. On Done: rebuild Table AST via `MarkupRewriter`, emit canonical GFM via `Markup.format()`, splice into source range. | User chose Option A. Popover is macOS-native (Calendar event editor, Reminders detail row, Mail VIP add). Preserves single-source-of-truth (no substitution). |
| **Table structural edits (add row / add column)** | Right-click inside a table → context menu items "Add Row Above / Below" + "Add Column Left / Right" → in-place AST splice via `TableStructureRewriter` + `Markup.format()` + `performEditingTransaction`. Does NOT open the popover. | Structural edits aren't in-cell edits — popover is for cell content. Add operations land in v0.2.7.2; remove deferred to v0.2.7.x. Matches Apple Numbers/Pages/Notes context-menu pattern. |
| Canonical body emission | `textStorage.string` directly | No reconstruction layer. Cell-edit commits write to storage via `performEditingTransaction`. |
| All text-storage mutations during cell-edit commit | Wrap in `textContentManager.performEditingTransaction { ... }` | Apple TextKit 2 sample mandate; batches layout, prevents hitches. |
| Materials / Liquid Glass | Reserved for floating chrome (the popover's surrounding panel only) — NOT used for inline body content | WWDC25 session 323 HIG. |
| Find / Replace | Works automatically — cells live in text storage as `\| cell \|` markdown | No special integration needed (vs. attachment model's deferred gap). |
| LineOffsetIndex UTF-8 vs UTF-16 latent bug | Documented as v0.2.7.x follow-up; NOT in scope | swift-markdown emits UTF-8 byte offsets; Pommora indexes UTF-16. Not triggered by this plan's small-range cell-edit splices. |

#### Visual spec — Apple-native values (LOCKED with citations)

| Element | Color | Weight | Other |
|---|---|---|---|
| Blockquote bar | `NSColor.separatorColor` (raw) | 3pt wide | full card height (continuous across multi-line); ~4pt inset from card leading edge |
| Blockquote bg | `Color.primary.opacity(0.06)` | — | full line-fragment width minus textInsets; 6pt corner radius (selective per first/middle/last/only fragment position); ~6pt vertical padding above first fragment + below last fragment |
| Blockquote indent | — | — | `paragraphStyle.headIndent = 20` (4pt card-edge → 3pt bar → 13pt clear → text) |
| Table borders | `NSColor.separatorColor` (raw) | 1pt | square corners (no radius); horizontal + vertical strokes |
| Table header bg | `Color.primary.opacity(0.04)` | — | full header row line-fragment rect |
| Table header text | inherits theme.bodyText | `.body.weight(.semibold)` | |
| Table cell padding | — | — | 13pt horizontal × 6pt vertical |
| Row striping | NONE | — | Apple Notes faithful |
| Popover surface | macOS-native NSPopover chrome | — | Materials only HERE (not inline) |
| Cell focus indicator | `Color.accentColor` | 1pt | `.overlay` border on focused cell — default macOS focus ring suppressed via `.focusEffectDisabled()` (Round 6) |
| Cell hover cursor | `NSCursor.iBeam` | — | hovering a cell shows iBeam, signaling "click to edit" without visible chrome (Round 6) |

**Critical correction from prior plan:** `NSColor.separatorColor` is already alpha-pre-attenuated by Apple (~0.29 light / ~0.6 dark). The prior plan's `.withAlphaComponent(0.8)` multiplier on the blockquote bar caused the "weak" rendering Nathan reported. Drop the multiplier.

#### Phase 1 — Blockquote (Apple Calendar event-card chrome) (~45 min)

**Files to modify:**

- [External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift):
  - Add small `Sendable` struct `BlockquoteMetadata { let sourceRange: NSRange }` colocated in the file — enables `drawBlockquote` to determine each fragment's position (first / middle / last / only) within the blockquote range
  - Add `nonisolated static let pommoraBlockquote = NSAttributedString.Key("PommoraBlockquote")` (value: `BlockquoteMetadata`)
  - Add `drawBlockquote(at:in:)`:
    - `enumerateAttribute(.pommoraBlockquote)` over the fragment range; bail if absent
    - Compute this fragment's position within `metadata.sourceRange`: `.only` (single-fragment quote), `.first` (top of multi-fragment), `.middle` (interior), `.last` (bottom)
    - Compute card rect: spans full line-fragment width minus `textContainerInset.width`; extends ~6pt above the fragment's text baseline if `.first` or `.only`, ~6pt below if `.last` or `.only` (no vertical padding on `.middle` — they butt seamlessly into neighbors)
    - Build a `CGPath` for the card with selective corner rounding (6pt radius):
      - `.only`: all 4 corners rounded
      - `.first`: top 2 corners rounded, bottom 2 square (joins seamlessly with next fragment)
      - `.middle`: all 4 corners square
      - `.last`: bottom 2 corners rounded, top 2 square
    - Fill the card with `NSColor.labelColor.withAlphaComponent(0.06)` (NSColor form of `Color.primary.opacity(0.06)`)
    - Draw the 3pt vertical bar INSIDE the card: x = `card.minX + 4`, y span = full card height for this fragment (top edge of `.first`/`.only` down through bottom edge of `.last`/`.only`; full fragment height on `.middle`), color = raw `NSColor.separatorColor`
  - Call from `draw(at:in:)` BEFORE `super.draw` so text renders on top of the card + bar
  - Extend `renderingSurfaceBounds` to cover the full card extent (line-fragment width + ~6pt vertical padding on `.first` / `.only` and `.last` / `.only` fragments)

- [External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift) `visitBlockQuote`:
  - Emit `.pommoraBlockquote = BlockquoteMetadata(sourceRange: <NSRange of the full blockquote>)` over the full blockquote range. (Note: payload upgraded from `Bool` to a struct so `drawBlockquote` can compute fragment-position-within-quote without re-scanning the text storage.)
  - Set `paragraphStyle.headIndent = 20` so text sits ~13pt clear of the bar (4pt card-edge → 3pt bar → 13pt clear → text)
  - **DROP** the existing `.backgroundColor` line (custom draw replaces it)

**Verification:** Type `> Quote line` → grey rounded-rect card (6pt corner radius, `Color.primary.opacity(0.06)` fill) + 3pt vertical separator-color bar inside the card (at ~4pt from card leading edge) + indented text within 300ms restyle. Card spans line-fragment width minus textInsets. Multi-line `> Line one\n> Line two` → ONE visually contiguous card: first fragment rounded top + square bottom, last fragment square top + rounded bottom, middle fragments all-square, bar runs full card height without visible breaks. Removing `>` removes the card on next restyle. Visual reference: Apple Calendar Today widget event card (Nathan's Round 6 screenshot).

**Deferred to v0.2.7.x:** nested blockquotes (stacked stripes via `locations[]` array on a richer attribute payload).

#### Phase 3 — Tables (Read-only inline + popover edit + drag-resize + structural context menu) (~6h, 4 stages)

> Numbering note: Phase 2 (HR) was scrubbed. Phase 3 + Stage 3.A/B/C/D identifiers preserved as-is so existing cross-references in this doc remain valid.

Four stages, each independently committable.

##### Stage 3.A — Inline grid rendering (~2h)

Apply Core Graphics overlay strokes in `MarkdownTextLayoutFragment.draw` to render tables as styled grids. Markdown source stays in text storage as `| Cell | Cell |` with low-opacity styling on the pipe + dash characters so they visually recede under the overlay.

**New file** `External/MarkdownEngine/Sources/MarkdownEngine/Renderer/PommoraTableMetadata.swift`:

```swift
@MainActor
struct PommoraTableMetadata: Sendable, Equatable {
    let id: UUID
    let tableNode: Table
    let sourceRange: NSRange
    let rowCount: Int
    let columnCount: Int
    let columnAlignments: [Table.ColumnAlignment?]
    /// Position in document among all tables (0-indexed). Used as frontmatter key.
    let tableIndex: Int
}
```

**Modify** [External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift) `visitTable`:
- Compute `NSRange` from `table.range` via existing `SourceRangeConverter`
- Build `PommoraTableMetadata` (with `tableIndex` incremented on each table visited)
- Emit `.pommoraTable = metadata` over the source range
- Apply low-opacity color (e.g. `NSColor.tertiaryLabelColor.withAlphaComponent(0.3)`) on pipe (`|`) and dash (`-`) characters via per-character attribute scan so they visually recede behind the grid overlay
- Apply `.font` bold weight on header-row cell ranges
- Apply per-cell `paragraphStyle.alignment` from `table.columnAlignments`

**Modify** [External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift):
- Add `nonisolated static let pommoraTable = NSAttributedString.Key("PommoraTable")` (value: `PommoraTableMetadata`)
- Add `drawTable(at:in:)`:
  - Detect attribute via `enumerateAttribute` over fragment range
  - For each line fragment in the table range, stroke horizontal 1pt line via Core Graphics using raw `NSColor.separatorColor`
  - For each column boundary (computed from per-row line-fragment text layout), stroke vertical 1pt line
  - Header row (`tableIndex == 0` row) gets bg fill at `Color.primary.opacity(0.04)` over its line-fragment rect (fill BEFORE the grid strokes so strokes overlap clean)
- Call from `draw(at:in:)` BEFORE `super.draw` so text renders on top
- Extend `renderingSurfaceBounds` to cover the table's full extent

**Verify:** Open `.md` with `| Header | Header |\n|---|---|\n| Cell | Cell |` → renders as styled grid (1pt separator borders, bold header, `.04` header bg, square corners, 13×6 padding from text layout natural spacing). Source `|` chars still selectable but visually quiet. Restyle on edit keeps grid visible.

##### Stage 3.B — Drag-resize column dividers + frontmatter persistence (~1.5h)

Add inline drag-resize for column boundaries. Persist widths to page frontmatter as a Pommora-namespaced extension.

**New file** `External/MarkdownEngine/Sources/MarkdownEngine/TextView/PommoraTableColumnState.swift`:

```swift
@MainActor
struct PommoraTableColumnState {
    /// Read column widths for the Nth table with the given column count from frontmatter.
    /// Returns nil if no match (caller falls back to auto-sized widths).
    static func readWidths(
        frontmatter: [String: Any],
        tableIndex: Int,
        columnCount: Int
    ) -> [CGFloat]?

    /// Write column widths back to frontmatter. Indexed by (tableIndex, columnCount) so
    /// small edits don't invalidate widths but column-count changes do.
    static func writeWidths(
        into frontmatter: inout [String: Any],
        tableIndex: Int,
        columnCount: Int,
        widths: [CGFloat]
    )
}
```

**Frontmatter schema** (Pommora extension):

```yaml
pommora_table_widths:
  - position: 0
    columns: 3
    widths: [120, 80, 100]
  - position: 1
    columns: 2
    widths: [200, 150]
```

**Modify** [External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift):
- In `drawTable`, if frontmatter has persisted widths for `(metadata.tableIndex, metadata.columnCount)`, apply them when computing column boundary X positions; else fall back to auto-sized widths (each cell's natural text width + padding, capped at container width)
- Expose column-boundary X positions as a property the coordinator can read for hit-testing

**Modify** [External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift):
- Override `cursorUpdate(with:)` (or use NSTrackingArea): when mouse is within ±2pt of a column boundary inside a `.pommoraTable` range, set cursor to `.resizeLeftRight`
- On `mouseDown` on a boundary: capture starting widths + mouse X
- On `mouseDragged`: update the in-memory width array → trigger `textLayoutManager.invalidateLayout(for: tableRange)` → grid redraws live
- On `mouseUp`: schedule a 300ms-debounced write to `viewModel.pageFile.frontmatter` via `PommoraTableColumnState.writeWidths` + atomic save

**Pommora app code update:** PageFile / frontmatter helpers extended to read/write `pommora_table_widths` key without clobbering other frontmatter. Verify against existing frontmatter-preservation tests.

**Verify:** Hover column divider → cursor becomes ↔. Drag → table redraws live, neighboring column compresses. Release → wait 300ms → page file on disk contains updated `pommora_table_widths` entry. Reload page → widths restored. Insert a row → widths preserved (column count unchanged). Add a column → widths reset (column count changed; fallback to auto).

##### Stage 3.C — Double-click popover editor (~2h)

Open a SwiftUI popover anchored to the table on double-click. Popover contains the styled editable grid.

**New file** `External/MarkdownEngine/Sources/MarkdownEngine/TextView/PommoraTablePopover.swift`:

```swift
struct PommoraTablePopover: View {
    let initialTable: Table
    @Binding var columnWidths: [CGFloat]
    let onCommit: (Table) -> Void
    let onCancel: () -> Void

    @State private var editedCells: [[String]] = []
    @FocusState private var focusedCell: CellID?

    var body: some View {
        VStack(spacing: 0) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<editedCells.count, id: \.self) { row in
                    GridRow {
                        ForEach(0..<editedCells[row].count, id: \.self) { col in
                            cellField(row: row, col: col)
                        }
                    }
                }
            }
            .background(gridStrokesOverlay)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Done") { onCommit(buildEditedTable()) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 400, idealWidth: 600)
        .onAppear { populateFromInitialTable() }
    }

    // cellField — TextField bound to editedCells[row][col], styled per visual spec
    // gridStrokesOverlay — Canvas drawing 1pt separatorColor strokes matching inline view
    // buildEditedTable — TableCellsRewriter walks initialTable, replaces cell content
}

struct CellID: Hashable { let row: Int; let col: Int }

/// MarkupRewriter that rebuilds a Table AST with new cell text content.
struct TableCellsRewriter: MarkupRewriter {
    typealias Result = Markup?
    let newCells: [[String]]
    // walk via Apple's MarkupRewriter pattern; at each Table.Cell, emit Cell([Text(newCells[r][c])])
    // preserve colspan / rowspan / alignment from source
}
```

**Modify** [External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift):
- On `mouseDown` with `clickCount == 2` inside a `.pommoraTable` range:
  - Compute table rect via `textLayoutManager.enumerateTextLayoutFragments` over `metadata.sourceRange`
  - Create `NSPopover` containing `NSHostingView<PommoraTablePopover>`
  - Show popover anchored to table rect with `.maxY` edge preference (popover appears below table; flips above if no room)

**On commit:**
- Wrap mutation in `textContentManager.performEditingTransaction { ... }`
- Build new markdown via `editedTable.format()` (Apple's `Markup.format()`)
- Splice into text storage at `metadata.sourceRange` (delete old range, insert new string)
- Set `isProgrammaticEdit = true` flag during splice to prevent restyle loop
- After splice, restyle picks up the change and rebuilds `PommoraTableMetadata` for the new range

**Cell styling spec (Round 6 — Gemini's recipe verified against Apple docs + corrected):**

Each `cellField` in the popover Grid:

```swift
TextField("", text: $editedCells[row][col], axis: .vertical)
    .textFieldStyle(.plain)
    .focusEffectDisabled()                                                    // strip macOS blue focus ring
    .multilineTextAlignment(alignment(for: col))                              // honor GFM columnAlignments
    .lineLimit(1...10)                                                        // bound vertical growth
    .focused($focusedCell, equals: CellID(row: row, col: col))
    .onKeyPress(.return) { moveFocus(to: .below); return .handled }           // Return commits, no newline
    .onKeyPress(.tab) { moveFocus(to: .right); return .handled }              // Tab moves right
    .padding(.horizontal, 13)                                                 // INSIDE the cell
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // expand to cell
    .background(isHeaderRow(row) ? Color.primary.opacity(0.04) : Color.clear)
    .overlay(alignment: .topLeading) {
        if focusedCell == CellID(row: row, col: col) {
            Rectangle().stroke(Color.accentColor, lineWidth: 1)
        }
    }
    .contentShape(Rectangle())                                                // whole cell is hit-testable
    .onTapGesture { focusedCell = CellID(row: row, col: col) }                // tap-anywhere focuses cell
    .onHover { $0 ? NSCursor.iBeam.push() : NSCursor.pop() }                  // iBeam = looks editable
```

**Corrections to Gemini's 4-point recipe (verified against developer.apple.com via Context7):**

| Gemini said | Correction | Why |
|---|---|---|
| `.textFieldStyle(.plain)` strips "the blue macOS focus ring" | Add `.focusEffectDisabled()` separately — `.plain` strips background + border but NOT the focus ring (separate AppKit concern) | Apple Notes cells suppress the default ring + draw a subtle accent overlay instead. |
| `.frame(maxWidth/Height: .infinity, alignment: .topLeading)` BEFORE the 13×6 padding | Order is `.padding` **then** `.frame` (padding inner, frame outer). Padding-then-frame puts padding INSIDE the cell-sized frame | The cell is the hit target; padding gives text breathing room WITHIN it. Reversed order would shrink the hit area. |
| (missing) | Add `.contentShape(Rectangle())` after `.frame` | Without it, taps on the transparent expanded-frame area don't register — SwiftUI hit-tests intrinsic content, not the explicit frame. |
| (missing) | Add `.onTapGesture { focusedCell = CellID(row, col) }` on the cell wrapper | The expanded hit area catches the tap but doesn't auto-route focus to the embedded TextField; route explicitly. Safe — the redundant-`@FocusState`-write anti-pattern (per `focus-patterns.md`) only fires when a `.focusable()` view's own gesture re-sets its own focus; here the tap is on the wrapper. |
| `TextField(..., axis: .vertical)` with "intercepting Return key" or a custom wrapper | Use `.onKeyPress(.return) { return .handled }` (macOS 14+). `.onSubmit` does NOT fire for `axis: .vertical` (newline-on-Return is by-design) | macOS-14+ canonical pattern; no NSViewRepresentable wrapper needed. |
| `.background(.clear)` | TextField with `.plain` style has no background. Real concern is layering: cell-wrapper background (header tint or `.clear`) → CG grid strokes (Canvas overlay) → TextField text on top | Z-order matters for the `.04` header tint + 1pt separator strokes + text to compose without occlusion. |

**Added beyond Gemini's recipe:**
- **Per-column alignment** from GFM `table.columnAlignments[col]` → `.multilineTextAlignment`. GFM carries alignment; we honor it.
- **`lineLimit(1...10)`** — soft cap so a runaway cell doesn't push the popover off-screen.
- **Subtle focus border** — 1pt accent overlay on focused cell; replaces the suppressed default ring with Apple-Notes-style indication.
- **`NSCursor.iBeam` on hover** — affordance that says "click to edit" without visible chrome (matches Notes / Pages / Numbers cell behavior).

**Verify:** Open table → double-click any cell → popover appears anchored to table → cells populated → edit cell text → Tab navigates → drag column divider in popover → Done → popover dismisses → text storage updated via `Markup.format()` → inline grid re-renders with new content + widths. Cancel → no changes. Click outside popover → dismisses without commit (NSPopover default). Hover any cell → iBeam cursor. Click on the transparent padding area of a cell → cell focuses (validates `.contentShape` + `.onTapGesture` wiring). Focused cell has 1pt accent overlay (no default macOS blue ring).

##### Stage 3.D — Add row / add column context menu actions (~30 min)

Right-click inside a `.pommoraTable` range surfaces "Add Row Above / Below" and "Add Column Left / Right" menu items. These actions edit the table structurally without opening the popover (they're not in-cell edits).

**Modify** [External/MarkdownEngine/Sources/MarkdownEngine/TextView/ContextMenu.swift](External/MarkdownEngine/Sources/MarkdownEngine/TextView/ContextMenu.swift):
- When the menu builds for a right-click inside a `.pommoraTable` range:
  - Determine the clicked row index + column index from the click point's relationship to the table's row line-fragment Y bounds + Stage 3.B's exposed column boundary X positions
  - Append four items: "Add Row Above", "Add Row Below", "Add Column Left", "Add Column Right"
- On selection: rebuild the Table AST via `TableStructureRewriter` (new), emit canonical GFM via `Markup.format()`, splice into `metadata.sourceRange` — same `performEditingTransaction` + `isProgrammaticEdit = true` wrapping as Stage 3.C's commit path

**Add to** `External/MarkdownEngine/Sources/MarkdownEngine/TextView/PommoraTablePopover.swift` (extending the `TableCellsRewriter` family from Stage 3.C):

```swift
/// MarkupRewriter that inserts a new empty row or column into a Table AST.
struct TableStructureRewriter: MarkupRewriter {
    enum Operation {
        case insertRow(at: Int)       // 0 = above first row; rowCount = below last row
        case insertColumn(at: Int)    // 0 = left of first col; columnCount = right of last col
    }
    let operation: Operation
    // walk to the Table node; rebuild rows/columns with new empty cell(s) inserted at the index
    // preserve all existing cell content, alignments, and column-count metadata
}
```

**Frontmatter width interaction:**
- Row insert → column count unchanged → widths preserved
- Column insert → column-count fingerprint changes → `pommora_table_widths` lookup misses → fall back to auto-sized widths. Documented behavior from Stage 3.B; nothing extra needed.

**Verify:**
- Right-click inside a cell → "Add Row Above", "Add Row Below", "Add Column Left", "Add Column Right" appear
- Click "Add Row Below" → new empty row materializes immediately below the clicked row in the grid; widths preserved; restyle picks up the change within 300ms
- Click "Add Column Right" → new empty column materializes immediately right of the clicked column; widths reset to auto (columnCount changed)
- Inserted cells contain an empty string; the cursor does NOT auto-snap into the new cell — user can double-click → popover to fill in content
- Right-click outside any `.pommoraTable` range → none of the four table items appear

#### Critical files

**Created (all in `External/MarkdownEngine/Sources/MarkdownEngine/`):**
- `Renderer/PommoraTableMetadata.swift` — wraps Apple swift-markdown `Table` AST node + sourceRange + UUID + tableIndex
- `TextView/PommoraTableColumnState.swift` — frontmatter persistence for `pommora_table_widths`
- `TextView/PommoraTablePopover.swift` — SwiftUI Grid + TextField + drag-resize editing UI + `TableCellsRewriter` + `TableStructureRewriter`

**Modified:**
- `Renderer/MarkdownTextLayoutFragment.swift`:
  - Add `.pommoraBlockquote` + `.pommoraTable` attribute keys
  - Add `drawBlockquote` (Apple Notes bar, no bg)
  - Add `drawTable` (Core Graphics grid overlay + bold header bg + persisted widths)
  - Expose column-boundary X positions for hit-testing
- `Styling/AppleASTSupplementalStyler.swift`:
  - Rewrite `visitBlockQuote`: emit `.pommoraBlockquote` + `headIndent = 16`; drop `.backgroundColor`
  - Rewrite `visitTable`: emit `.pommoraTable` metadata + low-opacity styling on pipes/dashes + header bold + per-cell alignment
- `TextView/Coordinator/NativeTextViewCoordinator.swift`:
  - Column-boundary cursor + drag handlers
  - Table double-click → NSPopover presentation
- `TextView/ContextMenu.swift` — table structural items "Add Row Above / Below" + "Add Column Left / Right" via `TableStructureRewriter` AST splice (Stage 3.D)

**Pommora app code:** PageFile / frontmatter helpers extended for `pommora_table_widths`. `PageEditorView.swift` untouched.

#### Reused existing Pommora patterns

- `drawThematicBreak` ([MarkdownTextLayoutFragment.swift:54-92](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L54-L92)) — blueprint for `drawBlockquote` AND `drawTable` (same `enumerateAttribute` + Core Graphics pattern)
- `drawCodeBlockBackground` (line 205-255) — blueprint for (a) **blockquote rounded-rect card + per-fragment corner selection** (Phase 1) — already uses the CGPath + bg-fill pattern at body-text scale, and (b) table header-row bg fill with selection clip-out behavior (Stage 3.A)
- `SourceRangeConverter` + `LineOffsetIndex` (AppleASTSupplementalStyler.swift:163-227) — SourceRange → NSRange (caveat: UTF-16 not UTF-8 — flagged as v0.2.7.x follow-up)
- `isProgrammaticEdit` flag ([NativeTextViewCoordinator.swift:50](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift#L50)) — guard during cell-edit splices
- `viewRect(forCharacterRange:using:)` ([NativeTextViewCoordinator.swift:248-263](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift#L248-L263)) — coord conversion for popover anchoring + hit-testing
- Apple swift-markdown `Markup.format()` (Sources/Markdown/Base/Markup.swift:384) — canonical GFM emission for cell-edit splices
- Apple swift-markdown `MarkupRewriter` (Sources/Markdown/Rewriter/MarkupRewriter.swift:12-20) — `TableCellsRewriter` adopts this protocol

#### Risk inventory (vs. prior plan: 4 of 7 risks ELIMINATED)

1. **Two-source-of-truth between text storage and viewModel.body — ELIMINATED.** Text storage contains literal markdown including pipes; `canonicalBody == textStorage.string` directly. Only cell-edit commits write to storage (via `Markup.format()` splice for the single edited table range).

2. **`tracksTextAttachmentViewBounds` Apple Forums bug 697381 — N/A.** No `NSTextAttachment` used.

3. **Restyle loop from substitution mutation — N/A.** No substitution. Cell-edit commits DO mutate storage but are wrapped in `performEditingTransaction` + `isProgrammaticEdit = true` guard (existing pattern).

4. **`Markup.format()` pipe-padding normalization** — applies on cell-edit commit only. Nathan accepted this earlier. Document in `PageEditor.md`.

5. **Find/Replace doesn't find cell text — ELIMINATED.** Cells live in text storage as `| cell |` markdown; system Find finds them natively.

6. **swift-markdown SourceRange UTF-8 vs Pommora UTF-16 latent bug — UNCHANGED (deferred to v0.2.7.x).** Same as prior plan; small scope here keeps risk acceptable.

7. **NSTextContentStorage `_fixSelectionAfterChangeInCharacterRange` — UNCHANGED (deferred).** Watch during testing; apply if observed.

**New risks introduced by Option A:**

8. **Column boundary hit-testing must be cache-aware.** Boundary X positions are computed from text layout; cache invalidation across edits matters. Test coverage required — assert boundaries update after row insert, cell edit, font scale change.

9. **`pommora_table_widths` indexed by `(position, columnCount)` loses widths on table reorderings or column-count changes.** Acceptable for v0.2.7.2 (rare operations); v0.2.7.x can migrate to per-table UUID keys in frontmatter if user feedback shows widths get dropped too often.

10. **Popover anchoring across page scroll.** If user scrolls the editor while the popover is open, popover must follow (NSPopover handles this for view-anchored cases; verify across split-view + sidebar resize).

#### Parallel-session compatibility

NavDropdown work (separate session) is sidebar-side. **No file overlap** — Phase 3 lives entirely inside `External/MarkdownEngine/` + a small PageFile frontmatter extension on the Pommora side. Per quirk #11, surface (not revert) unattributed working-tree changes encountered.

#### Verification (gold path)

**Blockquote (Phase 1):**
- Type `> Quote line` → grey rounded-rect card (6pt corner radius, `Color.primary.opacity(0.06)` fill) + 3pt vertical separator-color bar inside the card (at ~4pt from leading edge) + indented text within 300ms restyle
- Card width = line-fragment width minus textInsets; card extends ~6pt above the first fragment's text and ~6pt below the last fragment's text
- Multi-line `> Line one\n> Line two` → ONE visually contiguous card: first fragment rounded top + square bottom, middle fragments all-square, last fragment square top + rounded bottom, bar runs full card height without visible breaks between fragments
- Removing `>` removes the card on next restyle
- Nested `> > Inner` renders as single-level card in v0.2.7.2 (nesting deferred to v0.2.7.x)
- Side-by-side visual match: Apple Calendar Today widget event card (Nathan's Round 6 reference screenshot)

**Tables (Phase 3):**

*Inline rendering:*
- Open `.md` with `| Header | Header |\n|---|---|\n| Cell | Cell |` → renders as styled grid:
  - 1pt raw `separatorColor` borders (horizontal + vertical)
  - Bold semibold weight on header row
  - `Color.primary.opacity(0.04)` header bg
  - Square corners (no radius)
  - No row striping
  - Cell padding from natural text layout (~13×6 effective)
- Source pipes `|` and dashes `---` still selectable via drag (visually low-opacity behind grid)
- Edit a cell character → grid stays visible during 300ms restyle

*Drag-resize:*
- Hover column divider → cursor changes to `.resizeLeftRight`
- Drag → live width update → neighboring column compresses
- Release → after 300ms debounce, page file on disk contains `pommora_table_widths` entry with new widths
- Close + reopen page → widths restored from frontmatter
- Insert a row in the popover → widths preserved (columnCount unchanged)
- Add a column via right-click context menu (Stage 3.D) → widths reset to auto (columnCount changed)

*Popover edit:*
- Double-click any cell → NSPopover appears anchored to table rect with `.maxY` edge
- Popover shows identical styled grid + editable TextFields per cell
- Tab/Shift-Tab navigates cells; Return moves to cell below
- Drag column divider in popover → same live resize behavior
- Done → popover dismisses → text storage updated via `Markup.format()` splice → inline grid re-renders with new content
- Cancel → popover dismisses, no changes
- Click outside popover → dismisses (no commit — matches Calendar event-editor pattern)
- Esc → triggers Cancel via `.keyboardShortcut(.cancelAction)`

*Structural edits (right-click context menu):*
- Right-click inside any cell → menu shows "Add Row Above", "Add Row Below", "Add Column Left", "Add Column Right"
- Click "Add Row Below" → new empty row appears immediately below the clicked row; widths preserved; cursor does NOT auto-snap into the new row
- Click "Add Column Right" → new empty column appears immediately right of the clicked column; widths reset to auto (columnCount changed)
- These actions do NOT open the popover (they're structural, not cell-content edits — matches Apple Numbers/Pages/Notes)
- New cells start empty; user double-clicks → popover to populate content

*Integration:*
- Find/Replace (`⌘F`) finds text in cells natively (cells live in text storage)
- Selection across a table treats source range like any other text (highlight extends through hidden pipes — acceptable since they're low-opacity)
- Scroll while popover open → popover follows anchor

*Persistence:*
- Close + reopen page → table + widths preserved
- Multi-table page → each table's widths persisted independently by `(position, columnCount)` key
- Round-trip identical to original on disk EXCEPT for `Markup.format()` pipe-padding normalization on edited tables (Nathan accepted)

**Test suite + lint:**
- `xcodebuild test` via `builder` subagent — 197/197 baseline tests pass
- New tests:
  - `BlockquoteTests` — `drawBlockquote` `enumerateAttribute` coverage; `BlockquoteMetadata.sourceRange` populated correctly; first/middle/last/only fragment position detection from a known multi-fragment layout; corner-rounding per position (CGPath shape verification — top corners present on first, bottom on last, all-square on middle, all-rounded on only); `Color.primary.opacity(0.06)` fill resolved to `NSColor.labelColor.withAlphaComponent(0.06)`; `paragraphStyle.headIndent = 20`; multi-line continuity (no visible seam between adjacent fragments; bar runs full card height)
  - `TableRenderingTests` — grid line positions match line fragments + header styling + low-opacity pipes
  - `TableColumnWidthTests` — frontmatter persistence + restore by `(position, columnCount)` key + reset on column-count change
  - `TablePopoverEditTests` — `Markup.format()` round-trip + `TableCellsRewriter` AST integrity + preserve colspan/rowspan/alignment
  - `TablePopoverCellInteractionTests` — Tab/Shift-Tab walks the grid wrap-aware; Return commits + moves below (suppresses newline-on-Return for `axis: .vertical`); Esc cancels; tap on transparent padding area focuses the cell (validates `.contentShape(Rectangle())` + `.onTapGesture` wiring); per-column alignment from GFM `columnAlignments` drives `.multilineTextAlignment`; `lineLimit(1...10)` honored; iBeam cursor on hover; focus indicator is 1pt accent overlay (not default macOS blue ring)
  - `TableStructureEditTests` — `TableStructureRewriter` insert-row + insert-column AST integrity + frontmatter widths preserved on row insert vs reset on column insert + click-point → (row, col) hit-test math
  - `PageFrontmatterTests` extended — `pommora_table_widths` schema + co-existence with other frontmatter keys
- `swift format lint --strict --recursive Pommora/Pommora External/MarkdownEngine` exit 0

#### Execution rules

- **Model:** All subagent dispatches use Opus 4.7. Locked override.
- **Branch:** All commits land on `main` directly (quirk #13 override). Pull fresh main first to pick up NavDropdown's commits.
- **Build verification:** `builder` subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1).
- **Format:** `swift format lint --strict --recursive` exit 0 before every commit.
- **Push:** Nathan pushes manually unless explicitly authorized.
- **Docs in commits:** Commit `.claude/Handoff.md` + `.claude/Features/PageEditor.md` updates only on explicit request.
- **Phase commit cadence:** Phase 1 → Stage 3.A → Stage 3.B → Stage 3.C → Stage 3.D. Each independently green + lint-clean.

#### Deferred to v0.2.7.x

- **Fully-inline cell editing** (Option B layer) — apply if popover step actually bothers user in real use
- **Nested blockquotes** (locations[] stripe array)
- **Smart-inset bg for first/last lines of multi-line quotes** (Down-style)
- **Remove rows + columns** (right-click context menu — symmetric to Stage 3.D's add operations; add ships in v0.2.7.2, remove deferred)
- **NSTextContentStorage `_fixSelectionAfterChangeInCharacterRange`** workaround (apply if observed during testing)
- **UTF-8/UTF-16 `LineOffsetIndex` fix** for non-ASCII content (latent bug; not triggered by this patch)
- **Per-table UUID in frontmatter** instead of `(position, columnCount)` fingerprint (apply if reorderings lose widths too often)
- **Cell-level inline markdown rendering** (bold/italic inside cells) — borrow Textual's `WithInlineStyle` run-loop pattern

#### Open questions for execution-time

- **Version label:** Single `v0.2.7.2` covering both phases (total ~6.75h: Phase 1 ~45min + Phase 3 ~6h across four stages) is the recommended single bump. Confirm before first commit. HR/divider work ships separately under its own version label.
- **Frontmatter key naming:** `pommora_table_widths` — verify consistency with any existing Pommora frontmatter extension conventions (`pommora_<feature>_<concept>` vs. dot-notation).
- **Popover edge preference:** `.maxY` (below) preferred; verify NSPopover auto-flips above when no room (default behavior).
- **Low-opacity styling on pipes:** `NSColor.tertiaryLabelColor.withAlphaComponent(0.3)` is the proposed value; tune at implementation time so pipes are visible-but-quiet under the grid.

---

#### Why this design wins (refined post-Round-4)

**Apple-native visual specs are LOCKED to specific cited values** (raw `separatorColor`, 1pt borders, 13×6 padding for tables, `Color.primary.opacity(0.06)` fill + 6pt corner radius for blockquote card, no row striping). Round 4 Agent A pinned each value to an Apple-source citation; Round 6 swapped the blockquote target from Apple-Notes-minimal-bar to Apple-Calendar-event-card chrome per Nathan-supplied screenshot reference.

**~5.5h of complexity eliminated** vs. prior plan. The attachment+substitution machinery (6 stages, 7 risks, ~9-11h) collapses to a Core Graphics overlay (~2h) + drag-resize (~1.5h) + popover editor (~2h) + structural context menu (~30 min). Same Apple-Notes visual; same per-cell text editing UX; spatially modal for cell content + native right-click for shape changes — matches Apple Numbers/Pages/Notes.

**Files truly canonical at byte-level for non-edited tables; canonical-modulo-pipe-padding for edited tables.** Markdown source remains in text storage end-to-end. `canonicalBody == textStorage.string` at all times (no reconstruction layer). Find/Replace works on day 1. Atomic-write contract, frontmatter preservation, page-switch flush — all untouched.

**Risk-bounded.** Of the 7 risks in the prior plan, 4 are ELIMINATED (two-source-of-truth, attachment-bounds bug, restyle loops, Find/Replace gap), 1 is N/A. The remaining 2 (Markup.format pipe normalization — accepted; UTF-8/UTF-16 — out of scope) are documented. Three new risks (boundary hit-testing cache, frontmatter width-key fingerprinting, popover scroll-tracking) are scoped and testable.

**Future-extensible without migration.** If popover-edit UX disappoints, the v0.2.7.x layer for fully-inline editing sits on top without changing the file format. If user wants nested blockquotes, the single-attribute key extends naturally. Frontmatter widths can move to UUID-keyed in v0.2.7.x.

**Verification grounded.** Apple Notes blockquote screenshots + WWDC25 #323 HIG cited for every visual decision. Side-by-side comparison gates in the gold path.
