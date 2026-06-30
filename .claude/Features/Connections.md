### Connections

A **Connection** is an inline `[[Title]]` link in a Page's Markdown body that points to another Page. `[[` is the sole connection syntax — distinct from the `tier1` / `tier2` / `tier3` context-link properties that bind entities to Contexts.

A connection lives in exactly two places: the body (`[[Title]]`, canonical and Obsidian-readable) and a derived index edge rebuilt by scanning bodies. There's no frontmatter mirror, and resolution runs on an in-memory map, so the SQLite index is an accelerator the feature never depends on. A `[[Title]]` targets a Page. Contexts are reached only through tier relations; Tasks and Events are never connection targets.

### Features

#### II. Syntax + Scope

On disk a connection is just the bracketed title — `[[Title]]` — with no piped form, embedded id, or alias. The source is any Page body. The `![[ ]]` embed form and `{{ }}` are unsupported — both render as plain text — and a Page can't link itself.

#### II. Resolution

Titles match through one shared normalization — trimmed, case-insensitive — used by both resolution and autocomplete. A scanned title resolves to one of three states:

- **Resolved** — exactly one Page holds the title. The link is live: rendered styled and navigable, with its target's current ULID held in memory.

- **Ambiguous** — more than one Page holds the title. The link can't pick a target and stays inert until one side is renamed.

- **Phantom** — no Page holds the title. The link renders as literal bracketed text and goes live the moment a single matching Page appears.

#### II. Rename Cascade

Because identity is the title and the body carries no id, a rename **cascades**: renaming a target rewrites every body that references its old title, Nexus-wide, in one atomic pass. If the cascade fails, the file rename reverts. The index drives it, so it's targeted rather than a full scan.

#### II. Rendering

A resolved connection renders as styled colored inline text — never a chip — and a single click navigates to the Page. Ambiguous and phantom connections render as inert literal text with the brackets visible.

#### II. Autocomplete

Typing `[[` opens a search-filter panel above the caret listing Pages Nexus-wide; selecting one inserts its title. A bare typed title resolves identically.

### Architecture

#### II. Resolver + Index

The body is the source of truth — a connection exists because `[[ ]]` sits in the text. An in-memory map, from normalized title to the Page IDs holding it, resolves every link and drives the cascade. It's built from the page tree and refreshed on every in-app create, edit, delete, and rename. A `connections` index table mirrors the edges (source, target, normalized title, multiplicity, weight, and a resolved flag); it's regeneratable by re-scanning bodies and never authoritative. Full data layer → `Architecture.md`.

### Prospects

**Aliases + Duplicate Disambiguation:** A piped `[[Title|alias]]` form, and id-scoping so a connection to an ambiguous title can pick its target inline.

**Backlinks Panel:** A surface listing every Page that links to the current one. The edge data is captured in the index; the panel isn't built.

**Wider Targets + Embeds:** Connections from Context and Homepage block surfaces, Tasks and Events as targets, heading and block anchors (`#`, `#^`), and transclusion (`![[ ]]`).
