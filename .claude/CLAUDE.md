### Pommora — Project Instructions

#### Overview

A simpler Notion that's also a more capable Obsidian. Three top-level entities — **Pages** (Markdown documents), **Collections** (folder + `_collection.json` schema sidecar), **Spaces** (Notion-page-style block-composed surfaces) — plus **Items** (`.json`, Collection-bound row-shaped; open in a popover-style **Item window** — title + properties + 250-char description, not a tab or full page). Collections are typed at creation (`kind: "pages" | "items"`). SQLite indexes properties, links, and relations. Personal-first, Mac-first for v1, always open-source. Pommora's stack is **SwiftUI**; React+Electron is preserved as the contingency path.

#### Working with Nathan

- Non-coder, first agentic project. Nathan directs, Claude implements. Nathan does not write code.
- Mac user, always Mac. Lives in the Apple ecosystem.
- Values cohesion and simplicity over ecosystem reach or feature ceilings.
- Push back honestly when direction is unclear or a mistake is forming.
- Vocabulary may be imprecise — clarify before assuming.
- Studio-resident project; the Studio CLAUDE.md global rules and Nathan's NathanOS rules apply.

#### Stack

Locked to **SwiftUI**. Option 2 (WKWebView hosting Tiptap / Milkdown / BlockNote) is the likely direction for the Pages editor; Option 1 (native NSTextView via Clearly fork or original build) is the more ambitious alternative. React+Electron is preserved as the contingency path — translation methodology lives at `// ReactInfo//Contingency.md`; topic-based React reference at `// ReactInfo//` folder.

#### Core Principles

- **Three load-bearing constraints:** (1) **conceptual portability of functionalities** — file formats, schemas, design values, UX patterns survive a stack rebuild; (2) **cross-vault queryability + cloud sync compatibility** — the on-disk model maps cleanly to a cloud DB so sync arrives as additive translation; (3) **persistent immediate legibility for agents** — every entity is a file an external agent can read directly without tool-call round-trips. Full detail → `// Features//Architecture.md`.

- **Simplicity-first.** Don't add complexity that wasn't asked for. If it can be simplified, simplify it.

- **Files are canonical (≠ everything is Markdown).** Pages = `.md`. Collections = folder + `_collection.json` (carries the Collection's `kind`). Items = individual `.json` files (one per Item; filename = title); members live inside Items collections, loose Items live anywhere else. Spaces = `.space.json` block trees in `.pommora// spaces//`. Loose Pages and loose Items both exist; carry only built-in fields. SQLite is regeneratable index — no user data trapped in it.

- **Filename = title** everywhere. No `title` field; no `name` field on Items. Renaming in the UI renames the file. Independent UI titles are a Prospect.

- **Pages are Markdown, Spaces are blocks.** Pages are Markdown documents (one continuous Markdown stream) with two Pommora-specific rendering directives — `@Columns` (multi-column rendering of a section) and `:::callout` (outlined-box callout, distinct from blockquotes). Standard Markdown handles tables (GFM), blockquotes (standard `>` syntax, rendered with a filled background + left-side emphasis bar), dividers (`---`), and everything else. Headings are foldable by default (built-in UI, not a directive). **"Block-level features" as a project term belongs to Spaces only** — Spaces are the page-like canvases with drag-and-drop blocks.

- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips.

- **Relations stored by ID, displayed by title.** Frontmatter relation properties hold the target's ID (rename-safe); the editor renders the target's current title as styled colored inline text.

- **Move-strip rule.** Moving a member across Collections (or in/out of loose state) strips properties not in the destination schema — Notion-style; no quarantine. The user gets a simple confirmation warning listing which properties will be stripped.

- **Design system: SwiftUI primary + AppKit where needed + small Pommora-brand extensions.** Pommora uses SwiftUI semantic colors (`Color(.systemBackground)`, `.primary`, etc.), Materials (`Material.regular`, `.sidebar`), and Font scale (`.font(.body)`, `.font(.callout)`) wherever possible; AppKit is used directly via `NSViewRepresentable` where SwiftUI falls short (notably NSTextView/TextKit 2 for Option 1 editor, NSSplitView for splitter polish). Pommora-specific brand values (accent purple, code block colors, callout treatments) live in `// UI-UX//Design//Assets.xcassets` and `// Design//Color+Pommora.swift`. The full ~118-token Figma-built design system is React-flavored and lives in `// ReactInfo//Styling-Tokens.md` — only the WKWebView editor canvas (Option 2) uses CSS custom properties as tokens proper. Detail → `// UI-UX//UI-UX.md`.

- **The local file is the spec, not the render.** In-line views and computed values are referenced by directive, not inlined.

- **React pairing.** When meaningful Swift implementation work lands — something big OR something with an obvious React-side equivalent worth recording — add a paired note in the relevant `// ReactInfo// <topic>.md` file. Skip for trivial work. See `// ReactInfo//Contingency.md` for translation patterns.

#### Document Map

- `PommoraPRD.md` — high-level product requirements and architecture
- `Handoff.md` — current state and near-term priorities (read first at session start)
- `History.md` — locked decisions, brief
- `Framework.md` — phased roadmap to v1.0
- `Resources.md` — external resources catalog (Swift-baseline; React-side at `// ReactInfo//Resources.md`)
- `// Features//`
  - `Domain-Model.md` — entity overview, linking, sidebar, resolved decisions
  - `Pages.md` — on-disk shape, Markdown features + two rendering directives, editor surface, wikilinks
  - `Collections.md` — typed-Collection semantics, `_collection.json` schema, view types, loose entities, embedded views
  - `Items.md` — brief: row-shaped `.json` entries; on-disk, capabilities, Item window UI (popover, 250-char description), kind-picking guidance
  - `Spaces.md` — `.space.json` schema, drag-and-drop canvas, block types, referential framing
  - `Navigation-Bar.md` — single-row toolbar spec: layout, tab-strip behavior, hover-visibility modes, deferred features
  - `Sidebar.md` — sidebar selection language (subtle gray fill + accent foreground), light/dark behavior, deferred hover and keyboard nav
  - `Architecture.md` — what survives a stack rebuild (conceptual portability; Swift-locked, React as contingency)
  - `Properties.md` — property type catalog (shared between Pages and Items)
  - `Prospects.md` — post-v1 features and brainstormed ideas
- `// Guidelines//`
  - `UIX-Guide.md` — SwiftUI-native design philosophy, component conventions, AppKit interop
- `// Planning//`
  - (currently empty — v0.0 builds from `Framework.md` + `PommoraPRD.md` + `UIX-Guide.md`; React-locked predecessor at `// ReactInfo//v0.0.md`)
- `// ReactInfo//` — React+Electron contingency reference
  - `Contingency.md` — translation methodology and the update-obligation pattern
  - `ReactInfo.md` — folder index + preserved verified-findings appendix
  - `Editor.md`, `Spaces-DnD.md`, `Styling-Tokens.md`, `StateData.md`, `MacIntegration.md`, `Distribution.md` — topic files
  - `Symbols-guide.md` — React-side semantic-role icon indirection
  - `Resources.md` — React-side library catalog
  - `v0.0.md` — preserved React+Electron-locked v0.0 spec

##### Project root (outside `.claude//`)

- `// UI-UX//` — design system home. `Design//` holds `Assets.xcassets`, Pommora-brand Color/Font extensions, and design materials; `Components//` holds the SwiftUI component library. Guidelines: `UI-UX//UI-UX.md`, `UI-UX//Design//Design Guidelines.md`, `UI-UX//Components//Component Guidelines.md`.

#### Active Version

**v0.0 shipped.** Barebones three-pane shell (sidebar + main + hidden-by-default pop-out inspector) lives at [Pommora/Pommora/](Pommora/Pommora/). Build verified via `xcodebuild`. **Next: v0.1** — vault reads + functional tab chrome. Per-version spec lives in `Framework.md`. The React+Electron-locked predecessor spec for v0.0 is preserved at `// ReactInfo//v0.0.md`.
