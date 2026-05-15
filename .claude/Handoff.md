### Pommora — Session Handoff

#### Current State

**v0.0 shell shipped on SwiftUI / macOS Tahoe (26.5).** Three-pane shell at [Pommora/Pommora/](Pommora/Pommora/) — `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`; no content yet (tree, tabs, editor all land later). Stack, domain model, architecture, and locked decisions live in `PommoraPRD.md`, `History.md`, and `// Features//`. Read those for the model; this doc is for what's running and what's next.

**Doc cleanup pass (recent):** Tier 1 visual specs (Sidebar.md, Navigation-Bar.md, UIX-Guide.md) trimmed to principle-level after the small-chrome revert exposed Tahoe-rendering uncertainty. Rendered-outcome detail (hover states, tab-row sizing, control sizes, opacity values) now resolves at v0.1+ when content lands. PommoraPRD.md Domain Model + Design System sections trimmed to defer to canonical files.

---

#### Active Work — v0.0 shipped

**v0.0 shell scaffolded, polished, verified.** Implementation specifics (NavigationSplitView + inspector wiring, toolbar-style choice, animation curve, window sizing) locked in `History.md` "Features Implemented" and [ContentView.swift](Pommora/Pommora/ContentView.swift) / [PommoraApp.swift](Pommora/Pommora/PommoraApp.swift). Build verified via `xcodebuild`.

**Next: v0.1 — Vault reads + tabs functional.** Sidebar tree mirrors the user-picked vault (default `~// PommoraVault//`); clicking a `.md` file opens it as a tab; standard tab chrome (`+` / `×` / `Cmd+T` / `Cmd+W` / `Cmd+1..9`); open tabs + active tab persist. No parsing, no editor yet — main pane shows raw markdown.

**Brand accent + Figma deferred.** Xcode-default `AccentColor.colorset` stands in for v0.0; brand accent value picked at design lock. Figma design system being finalized as the React-side translation source; not consumed by the Swift build. Workflow at `// ReactInfo// Styling-Tokens.md`.

---

#### Pending Explorations

- **Audit findings to commit or defer** — Zod-equivalent validation + atomic writes + ULID per block, FTS5 `unicode61` mode, journal files for crash safety. Captured as findings, not committed. Decide once v0.2 (SQLite + watcher) implementation begins.

- **Optional spike before commit** — fork-Clearly assessment to size the native build gap (Option 1), or a WKWebView-host JS editor PoC (Option 2). Option 2 is well-documented via MarkEdit as the production reference; the `file://` ES-module block + `WKURLSchemeHandler` workaround is Apple-documented (see `// Features//Pages.md`). React-side reference at `// ReactInfo// Editor.md`.

- **Sidebar inline-chevron experiment (Finder pattern).** Spiked during v0.0 polish: dropping `DisclosureGroup` for Collections and hand-rolling chevron + member ForEach gives flush-left flat rows (Items/Spaces sit at sidebar leading edge, no chevron-column reservation). Reverted to `DisclosureGroup` for now (Apple-default Mail/Xcode pattern stays the v0.0 baseline). Nathan wants to revisit with v0.1+ content — specifically tighter chevron-to-icon spacing than Apple's default, with the rest of the sidebar visually matching. Full note → `// Features//Sidebar.md`.

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
- **Pommora-flavored Markdown is a dialect** — the `:::columns` and `:::callout` directives appear as inert notation in non-Pommora tools. Standard Markdown round-trips perfectly; the directives don't. Worth acknowledging this honestly in the docs rather than implying universal portability.
- **First-launch with an existing folder** — if the user picks a vault folder that already has `.pommora//` from a prior install, behavior isn't specified.
- **`@view` language in Spaces is imprecise** — docs use "`@view` directive" but `.space.json` is structured JSON with `embedded-collection-view` blocks. Either formalize a directive grammar or change the language to "embedded-view blocks."

---

#### Branch Status

Main branch. Remote: `https://github.com/Natertot215/Project-Pommora.git`. Studio working tree is the current source of truth.

#### Open Questions

- **Brand accent value.** Xcode default stands in for v0.0; final accent hue picked at design lock (not v0.0-blocking).
- **Editor option 1 vs option 2.** v0.3+ decision; doesn't affect v0.0.