### Pommora — Session Handoff

#### Current State

Domain model: **Pages** (`.md`), **Collections** (folder + `_collection.json`), **Spaces** (`.space.json` block trees), **Items** (`.json`, Collection-bound). Collections are typed at creation (`kind: "pages" | "items"`); Pages and Items can also exist loose (outside any Collection folder — built-in fields only, no schema-conforming properties). Moving members across Collections strips non-matching properties Notion-style.

Pages are Markdown documents with two Pommora rendering directives (`@Columns`, `:::callout`); headings are foldable by default; blockquotes and callouts are distinct constructs (blockquote = filled with left bar; callout = outlined). Spaces are block-composition surfaces — "block-level features" as a term belongs only to Spaces. Wikilinks render as styled colored inline text.

Sidebar: three top-level collapsible headings (Spaces / Saved / Collections), user-reorderable, default-collapsed. Spaces are leaf labels; Collections expand to their members; Saved is a non-operational placeholder in v1 (pinning is post-v1). Shell: three-pane (sidebar / main / inspector); both side panes drag-resizable from v0.0 (240 / 280 defaults). Inspector's default view is the property panel for the active Page; an AI chat interface (frontend to Nathan's existing local CLI — not an API integration) is a planned post-v1 addition. **Main pane is multi-tabbed** (Obsidian / Notion pattern); tab chrome renders in v0.0; tabs become functional in v0.1 as files open. **Items don't get tabs or the inspector** — they open in an **Item window** (popover anchored to trigger; Calendar-event-detail pattern; title + properties + 250-char description).

Vault: user-pickable on first launch (default suggestion `~// PommoraVault//`). App-internal config lives in `.pommora//` inside the vault (matches `.obsidian` convention). First launch seeds a `Homepage` Space; nothing else. Versioning is delegated to OS tools (Time Machine / git).

Architecture: **conceptual portability of functionalities** — file formats, schemas, design tokens, and UX patterns survive a stack rebuild; the codebase doesn't. Three load-bearing constraints: stack portability, cross-vault queryability + cloud sync compatibility, persistent agent legibility. Both stack paths (React+Electron, SwiftUI) audited; PRD has the dual-stack table.

No code yet — `.claude//` contains specs only.

---

#### Active Work — Figma Design System (in progress)

Design system built in Figma at the variable + visual-mock level: ~118 tokens (100% binding except for one technical text-lineHeight constraint), primitives and composed components rendered as gallery FRAMEs, three-pane shell mockup assembled. Nine Tag components converted to standalone COMPONENTs in the previous session; remaining 35 gallery items are still FRAMEs (can't be referenced as instances anywhere yet).

**Next concrete activity:** FRAME → COMPONENT_SET conversion per the plan at `// Planning// Figma Components 5-13.md`. Converts the 35 gallery FRAMEs into ~28 source COMPONENT_SETs (Button consolidates 4 galleries into one 40-variant SET; Disclosure consolidates 2 galleries). After conversion the Figma file becomes a real reusable component library that the React translation can consume directly.

**After conversion: the live React demo.** Translating components Figma → React + Tailwind in `UI-UX// Components//` and getting the localhost dev server running is what makes the React-flavored UIX outcome legible. Until the live demo exists, "what React feels like" is hypothetical and the stack decision can't be evidence-based.

**Visual direction (locked):**
- **Density:** Notion-comfortable (~1.6 body line-height)
- **Color treatment:** pastel-leaning, muted / desaturated
- **Typography:** SF Pro (sans) + SF Mono (mono); body 14, caption 12, micro 10 (added this session)
- **Chrome:** flat dark (no shadows except on overlays)
- **Rounding:** mixed scale by role (pill for tags, tight for buttons / toggles / labels, surface for cards / panels / modals)
- **Accent:** single-hue purple, 2×2 matrix (primary / secondary × active / muted), pastel-muted

**Accent rule (clarified this session):** components binding to "accent" use a single accent token slot (typically `accent/primary/active`). Interactive states (hover / active / focus / disabled) apply opacity / brightness modifiers on top — they do NOT swap between accent sub-tokens.

**Output landing zone:** `// UI-UX//` (project root, outside `.claude//`). Folder structure exists with guidelines docs only; `Design//` populates from Figma export, `Components//` populates from Figma → code translation. Components are born from Figma, never invented in code first.

---

#### Pending Decisions

1. **Stack — React+Electron or SwiftUI.** Both remain fully open. The decision hinges on two axes:

   - **Editor capability.** React: BlockNote / Tiptap are mature and easy to integrate. SwiftUI Option 2 (WKWebView + JS editor) uses the same JS libraries — Tiptap, Milkdown, BlockNote, or MarkdownEditor — making the editor capability gap with React effectively zero if Option 2 is chosen. SwiftUI Option 1 (native text editor) is more build work with TextKit 2 friction but delivers full native text behavior. Editor research is complete; the gap is well-understood on both sides.

   - **Rest-of-app build effort.** React: every component is a Figma → translation; Nathan owns the full UI surface; broader effort but full visual control. SwiftUI: native primitives (Table, LazyVGrid, NavigationSplitView, ReorderableVStack) handle much of the interaction for free; the Spaces and Collection view requirements are within documented SwiftUI capabilities; less total build effort for the shell.

   - **The trade:** React = full control at constant effort across everything. SwiftUI = effort concentrated at specific known edges, native Mac cohesion and iOS/iPad portability for free.

   - **Decision still open.** The Figma design system (functionally the React design system, per Nathan) is built and exports to either stack in 1-2 days. Sunk cost is symmetric — no Pommora code is committed on either stack. The decision rests on forward fit (Mac-first cohesion, iOS/iPad future, Linux/Windows openness, runtime simplicity), not on prototypes.

---

#### Pending Explorations (after the design system)

- **Audit findings to commit or defer** — `@parcel/watcher`, `@dnd-kit/core` v6 pin, Zod validation + atomic writes + ULID per block, FTS5 `unicode61` mode, journal files for crash safety, `gray-matter` alternatives. Captured as findings, not committed. Decide once stack lands.

- **Optional spike before commit** — BlockNote / Tiptap / Milkdown Markdown round-trip with a custom serializer for `:::columns` and `:::callout` (React), OR fork-Clearly assessment to size the native build gap (SwiftUI Option 1). SwiftUI Option 2 (WKWebView hosting a JS editor) is well-documented via MarkEdit as the production reference; the `file://` ES-module block + `WKURLSchemeHandler` workaround is Apple-documented (see `SwiftInfo.md`).

---

#### Open Questions

- **Stack:** React+Electron or SwiftUI? Decision is on forward fit (Mac-first cohesion, iOS/iPad future intent, Linux/Windows openness, runtime simplicity), not sunk cost — the Figma design system exports to either stack in 1-2 days and no Pommora code is committed yet.

Resolved prior session: Figma design system locked at variables + visual-mocks level (file at https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora); FRAME → COMPONENT_SET conversion plan saved at `// Planning// Figma Components 5-13.md`.

Resolved this session: Context7 research run across React and SwiftUI library claims — docs scrubbed of outdated framings (`@tiptap/markdown` is first-party, `@dnd-kit/core` v6 vs `@dnd-kit/react` split, BlockNote XL pricing softened, SwiftUI Option 2 WKWebView details formalized including `file://` ES-module block + `WKURLSchemeHandler` workaround).

---

#### Known Spec Gaps

Real items needing resolution before they bite, organized by when they'll surface.

##### Implementation risk

- **Editor risk — substantially de-risked, two stack-specific notes.** React: BlockNote and Tiptap are co-primary candidates (both fully open-source and free; BlockNote is batteries-included, Tiptap is the headless framework it's built on); Milkdown remains a pivot door. Pick at React commit. SwiftUI: two editor options documented in `SwiftInfo.md` — (1) native Swift editor: fork Clearly or build original on NSTextView/AppKit (source-with-decorations, fully native); (2) WKWebView hosting Tiptap, Milkdown, or BlockNote — likely direction if SwiftUI chosen; all three have solid Markdown translation; native SwiftUI shell wraps the editor canvas. A bounded spike (WKWebView-host JS editor PoC, or fork-Clearly assessment for the native path) would de-risk specifics before committing.

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

Main branch. Initial commit pushed to `Natertot215/Project-Pommora`. Studio root is current source of truth.
