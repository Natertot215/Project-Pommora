### Pommora — Session Handoff

#### Current State

Domain model: **Pages** (`.md`), **Collections** (folder + `_collection.json`), **Spaces** (`.space.json` block trees), **Items** (`.json`, Collection-bound). Collections are typed at creation (`kind: "pages" | "items"`); Pages and Items can also exist loose (outside any Collection folder — built-in fields only, no schema-conforming properties). Moving members across Collections strips non-matching properties Notion-style.

Pages are Markdown documents with two Pommora rendering directives (`@Columns`, `:::callout`); headings are foldable by default; blockquotes and callouts are distinct constructs (blockquote = filled with left bar; callout = outlined). Spaces are block-composition surfaces — "block-level features" as a term belongs only to Spaces. Wikilinks render as styled colored inline text.

Sidebar: three top-level collapsible headings (Spaces / Saved / Collections), user-reorderable, default-collapsed. Spaces are leaf labels; Collections expand to their members; Saved is a pinning placeholder until pinning ships. Shell: three-pane (sidebar / main / inspector); both side panes drag-resizable from v0.0 (240 / 280 defaults). Inspector hosts the property panel. **Main pane is multi-tabbed** (Obsidian / Notion pattern); tab chrome renders in v0.0; tabs become functional in v0.1 as files open.

Vault: user-pickable on first launch (default suggestion `~// PommoraVault//`). App-internal config lives in `.pommora//` inside the vault (matches `.obsidian` convention). First launch seeds a `Homepage` Space; nothing else. Versioning is delegated to OS tools (Time Machine / git).

Architecture: **conceptual portability of functionalities** — file formats, schemas, design tokens, and UX patterns survive a stack rebuild; the codebase doesn't. Three load-bearing constraints: stack portability, cross-vault queryability + cloud sync compatibility, persistent agent legibility. Both stack paths (React+Electron, SwiftUI) audited; PRD has the dual-stack table.

No code yet — `.claude//` contains specs only.

---

#### Active Work — Design System (Pre-v0.0)

The Figma design-system build is the next concrete activity. Build brief saved at `// Planning//Figma Prompt.md` — pasteable into a fresh session with `/figma-use` invoked. Architectural decisions and baseline token values are locked; Figma round 1 refines exact hex / sizing within the locked structure.

**Output landing zone:** the design system's outputs will feed `// UI-UX//` (project root, outside `.claude//`). Folder structure created with guidelines docs at `UI-UX//UI-UX.md`, `UI-UX//Design//Design Guidelines.md`, `UI-UX//Components//Component Guidelines.md`. `Design//` populates with exported tokens during v0.0 step 2 (Figma export); `Components//` populates with primitives + composed components during v0.0 step 3 (Figma → code translation). Pre-translation the folders are empty except for the guidelines docs — components are born from Figma, never invented in code first.

**Visual direction locked this session:**
- **Density:** Notion-comfortable (moderate breathing room, ~1.6 body line-height)
- **Color treatment:** Pastel-leaning, muted / desaturated
- **Typography:** SF Pro (sans) + SF Mono (mono) — system-native
- **Chrome:** Flat dark (no shadows except on overlays)
- **Rounding:** Mixed scale by role (pill for tags, tight for buttons / toggles / labels, surface for cards / panels / modals)
- **Accent:** Single-hue purple, 2×2 matrix (primary / secondary × active / muted); pastel-muted

Full token taxonomy and baseline hex values live in `// Planning//Figma Prompt.md`.

Design-system output (Variables + primitives + composed components) is stack-agnostic at the variable level. The output is what makes the stack decision evidence-based.

---

#### Pending Decisions

1. **Stack — React+Electron or SwiftUI.** Deferred behind the design-system build — Nathan is doing the React-flavored Figma design system first to see what the UIX outcome looks like before committing. Editor de-risked on both paths (React: BlockNote; SwiftUI: fork Clearly or build original native). Tradeoff is now non-editor: React = cross-platform horizon (Win / Linux without rewrite); SwiftUI = 100% Mac-ecosystem cohesion + iOS / iPad ships essentially free. Linux / Windows not on v1 path but not forever-closed; iOS / iPad is real long-term intent.

---

#### Pending Explorations (after the design system)

- **Audit findings to commit or defer** — `@parcel/watcher`, `@dnd-kit/core` v6 pin, Zod validation + atomic writes + ULID per block, FTS5 `unicode61` mode, journal files for crash safety, `gray-matter` alternatives. Captured as findings, not committed. Decide once stack lands.

- **Optional spike before commit** — Milkdown / BlockNote Markdown round-trip with a custom serializer for `:::columns` and `:::callout` (React), OR fork Clearly to see how far its native editor takes us before we'd extend it (SwiftUI), OR a minimal original native markdown editor to size the build effort (SwiftUI). Bounded; not required.

---

#### Open Questions

- **Stack:** React+Electron or SwiftUI? Decided after the design system is built (the React-flavored design system reveals what the React UIX outcome will feel like).

Resolved this session: Figma file created at https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora; build brief saved at `// Planning//Figma Prompt.md`.

---

#### Known Spec Gaps

Real items needing resolution before they bite, organized by when they'll surface.

##### Implementation risk

- **Editor risk — substantially de-risked, two stack-specific notes.** React: Milkdown may align better than BlockNote for "Pages are one Markdown stream" — pivot door, revisit at stack decision. SwiftUI: native markdown editing with Live Preview is solved territory (Clearly ships a working native AppKit editor; the source-with-decorations pattern is achievable on `TextEditor<AttributedString>` or `NSTextView`). Two open SwiftUI editor paths — fork Clearly, or build an original native editor — both documented in `SwiftInfo.md`. A bounded spike on the chosen stack (BlockNote round-trip for React; fork-Clearly assessment or minimal original-editor build for SwiftUI) would de-risk implementation specifics before committing.

- **`pommora.db` location.** PRD currently places the SQLite index at `.pommora// pommora.db` inside the user-pickable vault. If the user puts the vault on iCloud Drive, iCloud's file-conflict resolution can corrupt SQLite. Move to `~//Library//Application Support//Pommora//<vault-id>//`; the vault should hold only canonical content.

##### Framework version ordering (surfaces v0.6–v0.8)

- **v0.6 reads `_collection.json` before v0.8 introduces Collections.** Likely reorder: v0.6 (Collections: typed, schema, basic views) → v0.7 (Properties: simple) → v0.8 (Properties: rich) → v0.9 (more views).
- **Sidebar shape changes mid-flight.** v0.1 mirrors folder structure; v0.8 shifts to the three-heading logical model. Either the logical sidebar lands earlier with stub Collection support, or the v0.1 sidebar is throwaway scaffolding.
- **Saved heading is unscheduled.** Three-heading sidebar lands at v0.8 with Saved as a placeholder; pinning isn't on any numbered version. Either slot pinning into v0.9 / v0.10, or omit Saved from the v1 sidebar entirely until pinning ships.

##### SQLite / indexing

- **`links` table doesn't capture Space outlinks.** `from_kind` is currently `'page' | 'item'`; Spaces' widget blocks reference Collections / Pages / Items by ID without going into the index. Either expand `from_kind` to include `'space'` or document the limitation.
- **Pages lack `created_at` in frontmatter** (Items have it). Filesystem `mtime` gets clobbered by iCloud / git sync. Pages should have `created_at` in frontmatter for parity.

##### Underspecified UX edges

- **Filename collisions on creation** — auto-suffix (`Notes 2.md`)? Reject? Prompt? Wikilink-resolution collisions have rules; creation-time collisions don't.
- **Invalid filename characters** in titles (`/`, `:`, `\`) — silent replacement or rejection?
- **Pommora-flavored Markdown is a dialect** — the `:::columns` and `:::callout` directives appear as inert notation in non-Pommora tools. Standard Markdown round-trips perfectly; the directives don't. Worth acknowledging this honestly in the docs rather than implying universal portability.
- **First-launch with an existing folder** — if the user picks a vault folder that already has `.pommora//` from a prior install, behavior isn't specified.
- **`@view` language in Spaces is imprecise** — docs use "`@view` directive" but `.space.json` is structured JSON with `embedded-collection-view` blocks. Either formalize a directive grammar or change the language to "embedded-view blocks."

---

#### Branch Status

Main branch. Initial commit pushed to `Natertot215/Project-Pommora`. Studio root is current source of truth.
