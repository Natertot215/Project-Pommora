### Pommora — Session Handoff

#### Current State

**v0.0 shell shipped on SwiftUI / macOS Tahoe (26.5).** Committed and pushed to `main` at `4431420`. Three-pane shell at [Pommora/Pommora/](Pommora/Pommora/) — `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`.

Sidebar scaffolded with placeholder content: three top Items (no header), a collapsible **Spaces** section, and a collapsible **Collections** section with `DisclosureGroup`-based toggle-folders containing member rows. Native sidebar geometry — `.listRowInsets` overrides removed so flat-row icons align with Collection-row icons under the system's chevron-column reservation. Section headers explicit `.foregroundStyle(.secondary)` (string-shorthand `Section("Title", isExpanded:)` was rendering darker than Mail's reference tone on `.scrollContentBackground(.hidden)`). NSSearchField anchored to `.safeAreaInset(.top)`. Inspector pop-out wrapped in `withAnimation(.smooth(duration: 0.30))`.

No content yet — every row is a placeholder Label. Vault reads, tab chrome, and editor all land in v0.1+. Stack, domain model, architecture, and locked decisions live in `PommoraPRD.md`, `History.md`, and `// Features//`.

---

#### Next Session — Discussion Items

Three threads to open next session, in no particular order. They're interconnected (symbol convention informs vault-tree row rendering; filesystem connection produces real tab content; tab strip needs the symbol set to render correctly), so order of attack is a session-start decision.

1. **Standard-symbol convention / registry.** Currently every placeholder row uses `Image(systemName: "square.dashed")`. Nathan wants a stable registry — "for X type of entity, use Y SF Symbol" — so placeholder symbols become semantic from the start without per-instance specification. Open shape: JSON lookup file? Swift extensions (e.g., `Symbol.spaceIcon`, `Symbol.collectionIcon`)? Markdown reference table consumed by docs? Decide format, then populate initial mapping for Spaces / Collections / Items / Pages / loose entities / etc. React-side semantic-role pattern already exists at `// ReactInfo// Symbols-guide.md` — could inform the Swift shape.

2. **Filesystem connection (begin v0.1).** Make the sidebar mirror a user-picked vault. Default `~// PommoraVault//`. Read folder tree, surface `.md` files in the sidebar as actual Item rows (replacing placeholders). No parsing, no editor yet — clicking a file opens it as a tab; main pane shows raw markdown. Per Framework.md v0.1 scope. Folder-watching strategy + iCloud-safe storage paths need a brief decision.

3. **Top-bar tab implementation.** Single-row toolbar with the tab strip spec'd in `// Features//Navigation-Bar.md`. Standard tab chrome: `+` / `×` / `Cmd+T` / `Cmd+W` / `Cmd+1..9`; open tabs + active tab persist. Decide whether tabs land before or after the vault read so we know what content the strip displays during the build.

---

#### Pending Explorations

- **Audit findings to commit or defer** — Zod-equivalent validation + atomic writes + ULID per block, FTS5 `unicode61` mode, journal files for crash safety. Captured as findings, not committed. Decide once v0.2 (SQLite + watcher) implementation begins.

- **Optional spike before editor commit** — fork-Clearly assessment to size the native build gap (Option 1), or a WKWebView-host JS editor PoC (Option 2). Option 2 is well-documented via MarkEdit as the production reference; the `file://` ES-module block + `WKURLSchemeHandler` workaround is Apple-documented (see `// Features//Pages.md`). React-side reference at `// ReactInfo// Editor.md`.

- **Sidebar inline-chevron experiment (Finder pattern).** Spiked during v0.0 polish: dropping `DisclosureGroup` for Collections and hand-rolling chevron + member ForEach gives flush-left flat rows. Reverted to `DisclosureGroup` for the v0.0 baseline (Apple-default Mail/Xcode pattern). Revisit with v0.1+ content — Nathan wants tighter chevron-to-icon spacing than Apple's default, with the rest of the sidebar visually matching. Full note → `// Features//Sidebar.md`.

- **Sidebar selection language not built.** Sidebar.md documents intent (subtle gray fill + accent foreground, Mail-style). v0.0 ships with macOS-default sidebar selection (accent-blue fill + white foreground) because `.tint(_:)` doesn't propagate to NSTableView's source-list selection on macOS 26 Tahoe, and the AppKit introspection workaround was judged out of scope for v0.0. Revisit when content lands and the visual cost of bright-accent selection becomes concrete.

---

#### Known Spec Gaps

Real items needing resolution before they bite, organized by when they'll surface.

##### Implementation risk

- **Editor risk — substantially de-risked.** Two editor options documented in `// Features//Pages.md`: (1) native Swift editor — fork Clearly or build original on NSTextView/AppKit (source-with-decorations, fully native); (2) WKWebView hosting Tiptap, Milkdown, or BlockNote — likely direction; all three have solid Markdown translation; native SwiftUI shell wraps the editor canvas. A bounded spike (WKWebView-host JS editor PoC, or fork-Clearly assessment for the native path) would de-risk specifics before committing. React-side reference at `// ReactInfo// Editor.md`.

- **`pommora.db` location.** PRD currently places the SQLite index at `.pommora// pommora.db` inside the user-pickable vault. If the user puts the vault on iCloud Drive, iCloud's file-conflict resolution can corrupt SQLite. Move to `~//Library//Application Support//Pommora//<vault-id>//`; the vault should hold only canonical content.

##### Framework version ordering (surfaces v0.6–v0.8)

- **v0.6 reads `_collection.json` before v0.8 introduces Collections.** Likely reorder: v0.6 (Collections: typed, schema, basic views) → v0.7 (Properties: simple) → v0.8 (Properties: rich) → v0.9 (more views).
- **Sidebar shape changes mid-flight.** v0.1 mirrors folder structure; v0.8 shifts to the three-heading logical model. Either the logical sidebar lands earlier with stub Collection support, or the v0.1 sidebar is throwaway scaffolding.

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

`main`, pushed to remote `https://github.com/Natertot215/Project-Pommora.git` at `4431420`. Studio working tree is the current source of truth.

#### Open Questions

- **Brand accent value.** Xcode default stands in for v0.0; final accent hue picked at design lock (not v0.0-blocking).
- **Editor option 1 vs option 2.** v0.3+ decision; doesn't affect v0.0.
