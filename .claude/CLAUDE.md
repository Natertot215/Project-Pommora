### Pommora — Project Instructions

#### Overview

A simpler Notion that's also a more capable Obsidian. Composed of three top-level entity types: **Pages** (Markdown documents), **Collections** (folder + `_collection.json` schema sidecar — Make.md folder-notes pattern applied to Notion-style databases), **Spaces** (Notion-page-style block-composed surfaces). Collections additionally host **Items** — lightweight row-shaped entries (entries in `_items.json` alongside the schema) for database content that doesn't warrant a full Markdown Page. SQLite indexes properties, links, and relations for fast queries. Personal-first, Mac-first, always open-source. Stack portability across React+Electron and SwiftUI is the load-bearing constraint.

#### Working with Nathan

- Non-coder, first agentic project. Nathan directs, Claude implements. Nathan does not write code.
- Mac user, always Mac. Lives in the Apple ecosystem.
- Values cohesion and simplicity over ecosystem reach or feature ceilings.
- Push back honestly when direction is unclear or a mistake is forming.
- Vocabulary may be imprecise — clarify before assuming.
- Studio-resident project; the Studio CLAUDE.md global rules and Nathan's NathanOS rules apply.

#### Stack — Under Active Evaluation

Two viable paths: **React + Electron** or **SwiftUI**. Both produce identical on-disk Markdown and identical SQLite indexes; they differ in the editor surface and desktop shell. Full side-by-side stack table in `PommoraPRD.md` ("Stack — Under Active Evaluation" section).

The decision is deferred. Documentation across the project is written stack-agnostic at the capability level. Only `// Planning//v0.0.md` is hard-committed to a stack (currently React+Electron) and gets rewritten if the SwiftUI path is chosen.

#### Core Principles

- **Conceptual portability across stacks.** Pommora's *functionalities* (file formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design tokens, UX patterns) are designed to work across React+Electron and SwiftUI. If one stack ships and Pommora is later rebuilt in the other, that rebuild is guided translation work — not redesign. There's no enforced layer separation or "Core has zero UI imports" rule; portability comes from documented decisions, not code structure. See `// Features//Architecture.md` for what survives a rebuild.

- **Cross-vault queryability + cloud sync compatibility (second load-bearing constraint).** Collections aren't isolated — they're queryable and linkable from anywhere in the vault. The on-disk model must translate cleanly to a cloud DB (Collection → table, Pages and Items → rows, schema → columns) so future sync (e.g. Supabase) is additive, not a redesign. Frontmatter relations use IDs (rename-safe); body wikilinks use names (rewritten on rename).

- **Persistent immediate legibility for agents (third load-bearing constraint).** The vault is laid out so an agentic AI with filesystem access can read the entire structured graph — properties, relations, schemas, items, spaces — directly from files, without tool-call round-trips. This is the project's central differentiator: Notion's structure has to be queried piece by piece through an API (tool-mediated); Obsidian is locally legible but unstructured; Pommora gives a local agent persistent immediate access to a Notion-grade structured graph. Architectural decisions that would trade file-canonical legibility for app-internal convenience violate this constraint.

- **Simplicity-first.** Don't add complexity that wasn't asked for. If it can be simplified, simplify it.

- **Files are canonical (≠ everything is Markdown).** Every entity is a file an external tool can open and read. Only **Pages** are Markdown. **Collections** are folder + `_collection.json` (schema) + `_items.json` (item entries). **Spaces** are `.space.json` block trees in `_pommora// spaces//`. **Items** are JSON entries inside their Collection's `_items.json`. SQLite is purely a regeneratable index — no user data trapped in it.

- **Filename = title.** No `title` fields anywhere. Renaming in the UI renames the file. Independent UI titles are wishlist.

- **Pages are prose, Spaces are blocks.** Pages use a prose-first text editor (Bear / iA Writer style) with three block-level features for v1: `@Columns` (equidistant), callouts (visual container with optional color, no icons), and toggles (collapsible content blocks). In-line view embeds (`@View`) inside Pages are deferred to v2+ and are React-only when revisited. Spaces are page-like canvases with drag-and-drop blocks (Notion-style structured layout, not free positioning); embedded Collection views live there.

- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips. Across both stacks.

- **Design system lives in Figma / Storybook.** Variables use semantic role-based names (`surface// primary// bg`, never `bg-zinc-900`) so the same design exports to both CSS custom properties (React) and SwiftUI Color extensions.

- **The local file is the spec, not the render.** In-line views and computed values are referenced by directive, not inlined.

#### Document Map

- `PommoraPRD.md` — high-level product requirements and architecture (includes the dual-stack table)
- `Handoff.md` — current state and near-term priorities (read first at session start)
- `History.md` — locked decisions and architecture notes
- `Framework.md` — phased roadmap (12 versions to v1.0)
- `Resources.md` — external resources (libraries, documentation) catalog, organized by stack
- `ReactInfo.md` — React+Electron implementation reference; editor + Spaces + state-data + Mac integration + distribution
- `SwiftInfo.md` — SwiftUI implementation reference; parallel structure to ReactInfo.md
- `// Features//`
  - `Domain-Model.md` — entity overview, linking model, properties summary, sidebar pattern, resolved decisions
  - `Pages.md` — Pages on-disk, frontmatter, block-level features, editor surface (React BlockNote / Swift Phase A + Phase B), wikilinks
  - `Collections.md` — `_collection.json` schema, `_items.json` schema, view types, capabilities, loose Pages, embedded views
  - `Items.md` — brief: lightweight row-shaped entries inside Collections; on-disk, capabilities, Page-vs-Item choice
  - `Spaces.md` — `.space.json` schema, drag-and-drop canvas, block types, referential framing
  - `Architecture.md` — what survives a stack rebuild (conceptual portability of functionalities), what doesn't
  - `Properties.md` — property type catalog (shared between Pages and Items)
  - `Prospects.md` — potential post-v1 features and brainstormed ideas (not committed to any version)
- `// Planning//`
  - `v0.0.md` — current build spec (React+Electron-locked; rewritten if SwiftUI chosen)
- `// Guidelines//`
  - `UIX-Guide.md` — Figma source-of-truth, dual-export naming, tier model
  - Code conventions added as patterns emerge

#### Stack-conditional content convention

Pommora's stack call (React+Electron vs SwiftUI) remains genuinely open. To keep the two paths from blurring across the docs, stack-conditional content uses a labeling convention within shared docs.

**Format:**
- Agnostic content first (the "what" / "why" that's true regardless of stack)
- Where divergence exists: paragraph break, then `**For React**` (bold marker on its own line) with content underneath. Then `**For Swift**` (bold marker on its own line) with content underneath
- React first, Swift second
- Bold markers are paragraph-level, not headings
- Use only the label(s) needed; if only one stack has notes on a topic, only that label appears

**Exceptions where the convention does NOT apply:**
- **Comparison tables** (PRD dual-stack table, Architecture portability table) — the table format IS the cross-stack comparison
- **Catalog docs** (`Resources.md`) — existing per-stack heading structure reads better than inline labels for long bulleted catalogs
- **Stack-locked specs** (`Planning/v0.0.md`, `SwiftInfo.md`, `ReactInfo.md`) — entirely one-stack docs; no labeling needed

Compact summary principles (one-line core principles, brief callouts) may use parenthetical stack mentions instead of full label sections when the full treatment would bloat the summary.

#### Active Version

**v0.0** — App launches into a styled three-pane shell consuming design tokens. No editor, no data wiring. Spec at `// Planning//v0.0.md`. **Implementation is gated on the stack decision.**
