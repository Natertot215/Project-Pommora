### Pommora — Session Handoff

#### Current State

**v0.1a Nexus Foundation shipped** on SwiftUI / macOS Tahoe (26.4) — sandboxed picker, security-scoped bookmark persistence, `.nexus/` initialization, App Support paths, ULID identity, FolderTree filtering. Implementation at [Pommora/Pommora/Nexus/](Pommora/Pommora/Nexus/) (8 files). 25 unit tests pass. Design + Findings at [.claude/Planning/v0.1-nexus-foundation-design.md](.claude/Planning/v0.1-nexus-foundation-design.md).

**Sidebar visual scaffolding pass landed.** FolderTree-driven sidebar from v0.1a swapped for hardcoded placeholders (3 loose Items + Spaces × 3 + Collections × 3 × 3 Placeholders) to iterate selection chrome without real-data noise. `FolderTree.swift` / `SidebarNode.swift` / `SidebarRow.swift` stay in the target but dormant — re-wire next session.

**Selection language locked** — custom `SelectableRow` with tap-driven selection, `Color.gray.opacity(0.11)` rounded fill via `.listRowBackground`, accent foreground on icon + text, `Text.brightness(0.12)` to lift the accent over the fill. *Icon stays unbrightened* — that was the cross-context shading fix (SF Symbol `.brightness()` composites inconsistently across `Section` vs `DisclosureGroup` vs direct-`List`; `Text` is predictable). Fill rect inset 11pt horizontal + 2pt vertical (aligns with search field); row content padding 4pt leading / 0 trailing / 2pt vertical (4pt leading lines the icon up with where a chevron sits). `.symbolRenderingMode(.monochrome)` so foregroundStyle applies. Detail → [.claude/Features/Sidebar.md](.claude/Features/Sidebar.md). Trade-off: fill doesn't desaturate on window unfocus the way Finder/Mail do (no `NSVisualEffectView` + `.sourceList`).

**Detail pane:** `EmptyPane` wrapper dropped; `detail:` is bare `Color.clear`. Inspector toggle reverted to pre-807057d placement (inside `.inspector { }.toolbar { }`); inspector-segment Liquid Glass accepted as a known v0.0 visual gap.

---

#### Next Session — Discussion Items

Two threads remain after the foundation, plus an adjacent symbol-registry decision parked from before.

1. **Standard-symbol convention / registry.** Every sidebar row currently uses placeholder SF Symbols (`folder` / `doc.text` / `list.bullet.rectangle`) hardcoded in `SidebarRow.swift`. Nathan wants a stable registry — "for X type of entity, use Y SF Symbol" — so symbols become semantic without per-row specification. Open shape: JSON lookup file? Swift extensions (e.g., `Symbol.pageIcon`, `Symbol.collectionIcon`)? Markdown reference table? Decide format, populate mapping for Spaces / Collections / Items / Pages / loose entities, swap out the placeholders in `SidebarRow.swift`. React-side semantic-role pattern at `// ReactInfo// Symbols-guide.md` could inform the Swift shape.

2. **Rewire FolderTree → SidebarView (de-scaffold).** The placeholder Sections need to come out and the real folder content needs to come back. Reattach `SidebarView` to `NexusManager.currentNexus` + `FolderTree.buildTree(at:)` + render via `SidebarRow` (or its successor — the symbol-registry decision below may want a new row view). Keep the locked selection language (`SelectableRow` modifier chain) — apply it to real rows.

3. **v0.1b — Tab integration.** After de-scaffolding, clicking a `.md` row opens it as a tab in the top-bar tab strip; main pane shows raw markdown. Standard `+` / `×` / `⌘T` / `⌘W` / `⌘1..9` chrome per [Features/Navigation-Bar.md](Features/Navigation-Bar.md). Open tabs + active tab persist via `.nexus/state.json` inside the nexus (per the v0.1a state-file separation).

4. **v0.1a UX polish (deferred per direction).** All UI copy is functional/minimal — no welcome states, no error alerts, no descriptive panel text. Design pass picks these up. Specifically: empty-nexus state in the sidebar; first-launch picker-canceled empty state; error display surface for `NexusManager.pendingError`.

5. **Alternative directions surfaced end-of-session (no commitment).** Considered: (a) **Settings scene scaffold** — empty `Settings { TabView }` keyed to ⌘, that future features (Debug → Reset Nexus Bookmark, v0.12 accent/font) plug into; small commit, high optionality. (b) **File CRUD from sidebar UI** — add/rename/sort/delete; chunky, forces resolving filename-collision and sort-semantics underspecifications first. (c) **JSON schemas + Codable types** for the four entities (`PageFrontmatter`, `CollectionSchema`, `ItemFile`, `SpaceFile`) + atomic-write helpers + frontmatter parser (likely `apple/swift-markdown`); foundational, unblocks v0.2 indexer + CRUD writes + tab content rendering. **Recommended order if pivoting from Framework: schemas → settings → CRUD.** Tabs (Framework v0.1b) remains the locked default if no pivot.

---

#### Architectural Reconsideration — Vault Hierarchy (Pre-Decision)

Captured for thinking during remote sessions before any commitment.

**Proposal**: shift from the locked 3-entity model (Pages / Collections / Spaces + Items) to a 4-entity Capacities-style model (Spaces / Vaults / Collections / Items). Vaults become databases (schema holders); Collections become structural sub-categories within a Vault (sharing the Vault's schema); Items still live in Collections; Pages and Spaces semantics unchanged.

Filesystem reshape: `/Tasks/_collection.json + /Tasks/Buy groceries.json` → `/Planner/_vault.json + /Planner/Tasks/Buy groceries.json + /Planner/Goals/Q1 goals.json`. Example layout:

- **Planner** vault → Events / Tasks / To-do / Goals / Phases collections
- **Materials** vault → Documents / Records / Prompts / Assignments collections
- **Bookmarks** vault → its own collections

**Why it's meaningful**: domain-model change, not refactor. Categorization moves from a property ("group by Type") to a structural fact (which Collection a member lives in) — matches how Nathan describes actually organizing.

**Why now is the cheapest moment**: only v0.1a foundation has shipped. No SQLite schema, property UI, view configurations, editor, or tabs depend on the 3-entity model yet. Cost rises sharply after v0.2 (SQLite schema) and v0.6 (property UI).

**Open questions to resolve before docs revise:**
1. Collection kind — Vault-level (whole Vault is Pages or Items) or Collection-level (mixed kinds inside a Vault allowed)?
2. Property scope — Vault-wide (all Collections share schema) or per-Collection (each Collection overrides)?
3. Loose entities — still allowed outside any Vault, or must everything live in a Vault?
4. Sidebar shape — "Spaces / Saved / Vaults" with Collections nested? Or restructure further?
5. Naming — "Vault" collides with Obsidian's name for the whole user folder (Pommora calls that a Nexus). Alternatives: Database, Catalog, Domain, Pool, Store. Or commit to "Vault" knowing the overlap.
6. Vault semantics — does a Vault have a viewable face (saved views, schema editor) or is it invisible scaffolding?

**Recommended decision approach (for the gym-planning session):**
1. Pick a name first (docs need a word)
2. Write 3–5 real scenarios (Planner / Materials / Calendar / your actual stuff) — concretely list Vault, Collections, properties per category. Validates the model against real usage before docs are touched.
3. Resolve questions 1–6 against those scenarios
4. Then revise docs: `Domain-Model.md` first (top of the architecture), cascade through `Collections.md`, `Items.md`, new `Vaults.md`, `Properties.md`, `Sidebar.md`, `PommoraPRD.md`, `Framework.md`

**Claude's recommendation**: do it if the structural-categorical model genuinely matches how you organize (Capacities-style). The architectural cost only goes up from here. The "Vault" name collision is the one real friction worth deciding deliberately.

---

#### Pending Explorations

- **Audit findings to commit or defer** — Zod-equivalent validation + atomic writes + ULID per block, FTS5 `unicode61` mode, journal files for crash safety. Captured as findings, not committed. Decide once v0.2 (SQLite + watcher) implementation begins.

- **Optional spike before editor commit** — fork-Clearly assessment to size the native build gap (Option 1), or a WKWebView-host JS editor PoC (Option 2). Option 2 is well-documented via MarkEdit as the production reference; the `file://` ES-module block + `WKURLSchemeHandler` workaround is Apple-documented (see `// Features//Pages.md`). React-side reference at `// ReactInfo// Editor.md`.

- **Sidebar inline-chevron experiment (Finder pattern).** Spiked during v0.0 polish: dropping `DisclosureGroup` for Collections and hand-rolling chevron + member ForEach gives flush-left flat rows. Reverted to `DisclosureGroup` for the v0.0 baseline. The current scaffold keeps `DisclosureGroup` + a 4pt-tighter leading padding (6pt vs Apple's 10pt default) as a partial answer to the chevron-spacing concern. Revisit hand-roll if the gap still reads loose against real content. Detail → [.claude/Features/Sidebar.md](.claude/Features/Sidebar.md).

---

#### Known Spec Gaps

Real items needing resolution before they bite, organized by when they'll surface.

##### Implementation risk

- **Editor risk — substantially de-risked.** Two editor options documented in `// Features//Pages.md`: (1) native Swift editor — fork Clearly or build original on NSTextView/AppKit (source-with-decorations, fully native); (2) WKWebView hosting Tiptap, Milkdown, or BlockNote — likely direction; all three have solid Markdown translation; native SwiftUI shell wraps the editor canvas. A bounded spike (WKWebView-host JS editor PoC, or fork-Clearly assessment for the native path) would de-risk specifics before committing. React-side reference at `// ReactInfo// Editor.md`.

- **`nexus.db` location** — *resolved in v0.1a.* SQLite index lives at `~//Library//Application Support//com.nathantaichman.Pommora//nexuses//<nexus-id>//nexus.db` per Apple Foundation + GRDB.swift recommendation. Per-nexus subdir keyed by ULID survives nexus rename/move; marked `isExcludedFromBackupKey` for iCloud-Backup quota hygiene. The nexus folder stays purely canonical content.

##### Framework version ordering (surfaces v0.6–v0.8)

- **v0.6 reads `_collection.json` before v0.8 introduces Collections.** Likely reorder: v0.6 (Collections: typed, schema, basic views) → v0.7 (Properties: simple) → v0.8 (Properties: rich) → v0.9 (more views).
- **Sidebar shape changes mid-flight.** v0.1 mirrors folder structure; v0.8 shifts to the three-heading logical model. Either the logical sidebar lands earlier with stub Collection support, or the v0.1 sidebar is throwaway scaffolding.

##### SQLite / indexing

- **`links` table doesn't capture Space outlinks.** `from_kind` is currently `'page' | 'item'`; Spaces' widget blocks reference Collections / Pages / Items by ID without going into the index. Either expand `from_kind` to include `'space'` or document the limitation.
- **Pages lack `created_at` in frontmatter** (Items have it). Filesystem `mtime` gets clobbered by iCloud / git sync. Pages should have `created_at` in frontmatter for parity.

##### Underspecified UX edges

- **Filename collisions on creation** — auto-suffix (`Notes 2.md`)? Reject? Prompt? Wikilink-resolution collisions have rules; creation-time collisions don't.
- **Pommora-flavored Markdown is a dialect** — the `:::columns` and `:::callout` directives appear as inert notation in non-Pommora tools. Standard Markdown round-trips perfectly; the directives don't. Worth acknowledging this honestly in the docs rather than implying universal portability.
- **First-launch with an existing folder** — *resolved in v0.1a.* `.nexus/` already present → load existing `nexus.json`, skip init. Empty folder → silent init. Non-empty folder without `.nexus/` → confirm dialog before init.
- **`@view` language in Spaces is imprecise** — docs use "`@view` directive" but `.space.json` is structured JSON with `embedded-collection-view` blocks. Either formalize a directive grammar or change the language to "embedded-view blocks."

---

#### Branch Status

`main`. Working tree clean. Latest commit is this session's sidebar visual scaffolding pass — folds the in-session revert of 807057d (inspector toolbar experiment), the `SelectableRow` + locked selection chrome, the `EmptyPane` removal, and the doc sync into one commit.

#### Open Questions

- **Brand accent value.** Xcode default stands in for v0.0; final accent hue picked at design lock (not v0.0-blocking).
- **Editor option 1 vs option 2.** v0.3+ decision; doesn't affect v0.0.
