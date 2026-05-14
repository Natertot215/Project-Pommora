### Pommora — Session Handoff

#### Current State

Stack locked to **SwiftUI**. Domain model: **Pages** (`.md`), **Collections** (folder + `_collection.json`), **Spaces** (`.space.json` block trees), **Items** (`.json`, Collection-bound). Collections are typed at creation (`kind: "pages" | "items"`); Pages and Items can also exist loose (outside any Collection folder — built-in fields only, no schema-conforming properties). Moving members across Collections strips non-matching properties Notion-style.

Pages are Markdown documents with two Pommora rendering directives (`@Columns`, `:::callout`); headings are foldable by default; blockquotes and callouts are distinct constructs (blockquote = filled with left bar; callout = outlined). Spaces are block-composition surfaces — "block-level features" as a term belongs only to Spaces. Wikilinks render as styled colored inline text.

Sidebar: three top-level collapsible headings (Spaces / Saved / Collections), user-reorderable, default-collapsed. Spaces are leaf labels; Collections expand to their members; Saved is a non-operational placeholder in v1 (pinning is post-v1). Shell: three-pane (sidebar / main / inspector); both side panes drag-resizable from v0.0 (240 / 280 defaults). Inspector's default view is the property panel for the active Page; an AI chat interface (frontend to Nathan's existing local CLI — not an API integration) is a planned post-v1 addition. **Main pane is multi-tabbed** (Obsidian / Notion pattern); tab chrome renders in v0.0; tabs become functional in v0.1 as files open. **Items don't get tabs or the inspector** — they open in an **Item window** (popover anchored to trigger; Calendar-event-detail pattern; title + properties + 250-char description).

Vault: user-pickable on first launch (default suggestion `~// PommoraVault//`). App-internal config lives in `.pommora//` inside the vault (matches `.obsidian` convention). First launch seeds a `Homepage` Space; nothing else. Versioning is delegated to OS tools (Time Machine / git).

Architecture: **conceptual portability of functionalities** — file formats, schemas, design values, and UX patterns would survive a stack rebuild to React+Electron; the codebase wouldn't. Three load-bearing constraints: stack portability, cross-vault queryability + cloud sync compatibility, persistent agent legibility. Pivot methodology at `// ReactInfo//Contingency.md`.

No code yet — `.claude//` contains specs only.

---

#### Active Work — v0.0 build-ready; Figma re-pass (contingency) ongoing

**v0.0 is buildable from the current docs.** Framework v0.0 carries the build spec (deployment target macOS 26+, window dimensions, pane defaults, what renders); PRD covers shell + tab chrome; UIX-Guide covers SwiftUI conventions + AppKit interop. Pre-v0.0 step is one Asset Catalog entry (`AccentColor.colorset` with light/dark pastel-muted purple) — Nathan picks the hex at build time. `Color+Pommora.swift` and `Font+Pommora.swift` can be empty stubs until their consuming features land (code colors v0.3+, callout / blockquote v0.3–v0.4).

**Figma re-pass (contingency-side, ongoing):** Nathan is finalizing the Figma design system. The Figma file is the React-side translation source if a future pivot is ever needed; for Swift, the design is implemented in SwiftUI native idioms — the Figma file isn't consumed by the Swift build. Figma-tool workflow at `// ReactInfo//Styling-Tokens.md`.

**Visual direction (locked):**
- **Density:** Notion-comfortable
- **Color treatment:** pastel-leaning, muted / desaturated
- **Typography:** SF Pro (sans) + SF Mono (mono), system-native via SwiftUI Font scale
- **Chrome:** flat dark (no shadows except on overlays)
- **Rounding:** mixed scale by role (pill for tags, tight for buttons / toggles / labels, surface for cards / panels / modals)
- **Accent:** pastel-muted purple, single-hue. Interactive states (hover / active / focus / disabled) apply opacity / brightness modifiers on top of `Color.accentColor` — not separate accent values.

---

#### Pending Explorations

- **Audit findings to commit or defer** — Zod-equivalent validation + atomic writes + ULID per block, FTS5 `unicode61` mode, journal files for crash safety. Captured as findings, not committed. Decide once v0.0 implementation begins.

- **Optional spike before commit** — fork-Clearly assessment to size the native build gap (Option 1), or a WKWebView-host JS editor PoC (Option 2). Option 2 is well-documented via MarkEdit as the production reference; the `file://` ES-module block + `WKURLSchemeHandler` workaround is Apple-documented (see `// Features//Pages.md`). React-side reference at `// ReactInfo// Editor.md`.

---

#### Open Questions

(none currently)

Resolved: Stack call → SwiftUI. Figma design system locked at variables + visual-mocks level; React-side detail preserved at `// ReactInfo// Styling-Tokens.md`. Context7 research run across React and SwiftUI library claims — `@tiptap/markdown` is first-party, `@dnd-kit/core` v6 vs `@dnd-kit/react` split, BlockNote XL pricing, SwiftUI Option 2 WKWebView details (including `WKURLSchemeHandler` workaround) all documented.

---

#### Known Spec Gaps

Real items needing resolution before they bite, organized by when they'll surface.

##### Implementation risk

- **Editor risk — substantially de-risked.** Two editor options documented in `// Features//Pages.md`: (1) native Swift editor — fork Clearly or build original on NSTextView/AppKit (source-with-decorations, fully native); (2) WKWebView hosting Tiptap, Milkdown, or BlockNote — likely direction; all three have solid Markdown translation; native SwiftUI shell wraps the editor canvas. A bounded spike (WKWebView-host JS editor PoC, or fork-Clearly assessment for the native path) would de-risk specifics before committing. React-side reference at `// ReactInfo// Editor.md`.

- **`pommora.db` location.** PRD currently places the SQLite index at `.pommora// pommora.db` inside the user-pickable vault. If the user puts the vault on iCloud Drive, iCloud's file-conflict resolution can corrupt SQLite. Move to `~//Library//Application Support//Pommora//<vault-id>//`; the vault should hold only canonical content.

##### Framework version ordering (surfaces v0.6–v0.8)

- **v0.6 reads `_collection.json` before v0.8 introduces Collections.** Likely reorder: v0.6 (Collections: typed, schema, basic views) → v0.7 (Properties: simple) → v0.8 (Properties: rich) → v0.9 (more views).
- **Sidebar shape changes mid-flight.** v0.1 mirrors folder structure; v0.8 shifts to the three-heading logical model. Either the logical sidebar lands earlier with stub Collection support, or the v0.1 sidebar is throwaway scaffolding.
- ~~Saved heading is unscheduled.~~ **Resolved:** Saved is a non-operational placeholder heading in v1; pinning is out of v1 scope and ships post-v1.

##### SQLite / indexing

- **`links` table doesn't capture Space outlinks.** `from_kind` is currently `'page' | 'item'`; Spaces' widget blocks reference Collections / Pages / Items by ID without going into the index. Either expand `from_kind` to include `'space'` or document the limitation.
- **Pages lack `created_at` in frontmatter** (Items have it). Filesystem `mtime` gets clobbered by iCloud / git sync. Pages should have `created_at` in frontmatter for parity.

##### Underspecified UX edges

- **Filename collisions on creation** — auto-suffix (`Notes 2.md`)? Reject? Prompt? Wikilink-resolution collisions have rules; creation-time collisions don't.
- ~~Invalid filename characters in titles.~~ **Out of scope** — Pommora doesn't enforce filename validity beyond what the OS enforces; that's an Obsidian-style concern, not Pommora's.
- **Pommora-flavored Markdown is a dialect** — the `:::columns` and `:::callout` directives appear as inert notation in non-Pommora tools. Standard Markdown round-trips perfectly; the directives don't. Worth acknowledging this honestly in the docs rather than implying universal portability.
- **First-launch with an existing folder** — if the user picks a vault folder that already has `.pommora//` from a prior install, behavior isn't specified.
- **`@view` language in Spaces is imprecise** — docs use "`@view` directive" but `.space.json` is structured JSON with `embedded-collection-view` blocks. Either formalize a directive grammar or change the language to "embedded-view blocks."

---

#### Branch Status

Main branch. Remote: `https://github.com/Natertot215/Project-Pommora.git`. Studio working tree is the current source of truth.
