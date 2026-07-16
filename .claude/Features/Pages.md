### Pages

A Page is one Markdown file inside a [Collection](Collections.md) — the only operational entity that holds free prose. A Page belongs to one Collection (the one whose folder it physically lives in, at any depth) and conforms to that Collection's property schema.

A Page is a single `.md` file: YAML frontmatter for identity and property values, then a Markdown body for prose. Membership is by location — a file inside a Collection, or one of its Sets at any depth, is a Page in that Collection; there's no container field. The filename is the title — there's no `title` field, and renaming in the UI renames the file. The body is standard Markdown plus Pommora's callout directive, edited in [[Studio/Pommora/II. Features/MarkdownPM|MarkdownPM]] → `MarkdownPM.md`.

### Features

#### II. On-Disk Shape

Frontmatter carries `id` (a ULID), an optional `icon`, the per-tier relations `tier1` / `tier2` / `tier3` (bare ULID arrays), `properties` (values keyed by property ID), `created_at` / `modified_at`, and `cover` (a Nexus-relative page-banner path). Property values conform to the owning Collection's schema. Foreign frontmatter keys — and YAML comments — are preserved by value on every write: the writer re-serializes only the modeled keys and never reconstructs the object.

#### II. Title + Membership

The filename minus `.md` is the title — there's no `title` field, and a rename is a file rename. Within a folder, names must be unique: a colliding create auto-disambiguates (`Note 2`, `Note 3`, …) and a colliding rename is rejected. Titles aren't unique Nexus-wide, though — two Pages in different folders can share one, and a `[[Title]]` to a shared title resolves as ambiguous (→ `Connections.md`). Membership is purely positional: moving the file between [[Collections]] or [[Studio/Pommora/II. Features/PageSets|PageSets]] changes its membership, with no field to update. Moving across Collections brings the Page under the destination schema → `Collections.md`.

#### II. Properties Surface

A Page's property values live in its frontmatter, keyed by property ID, conforming to the Collection's schema. The editing surface — a property panel attached to the Page — is Pending: values round-trip on disk and through the index, but there's no UI to view or edit them on a Page. The catalog and schema mechanics → `Properties.md`.

#### II. Opening Behavior

Clicking a Page opens it in the main detail pane, replacing the previous selection; one Page is open at a time, and the editor auto-saves on a debounce. A Collection can route its Pages to a compact preview card instead via `open_in`, but that routing is Pending — Pages open in the main pane. Routing → `Collections.md`.

#### II. Connections

A Page's body can hold inline `[[Title]]` [[Studio/Pommora/II. Features/Connections|Connections]] — Obsidian-compatible wikilinks that render as styled colored inline text and navigate on click. Resolution runs on an in-memory map built from the page tree. Canonical spec → `Connections.md`; the `tier1` / `tier2` / `tier3` context-link counterpart → `Properties.md`.

#### II. Editor UI State

Per-page editor UI state lives in per-machine files under `.nexus/`, never in the portable `.md`: heading-fold state in `.nexus/folds.json` and per-table heading-column choices in `.nexus/tableHeadingColumns.json`, each keyed by page ID. Keeping this state out of the frontmatter leaves the `.md` out of cloud-sync churn.

### Architecture

#### II. Read + Write

A Page reads through a lenient split of the `---\n<yaml>---\n<body>` envelope — a missing or unterminated fence yields an all-body read, so a frontmatter-less Markdown file still opens, and one legacy separator blank line after the closing fence is stripped on read (writes never emit one, so a note never opens with an empty line). Writes go through the same comment-preserving merge and an atomic temp-file-plus-rename. The editor binds to the body and debounces saves; frontmatter is a typed object the editor can't corrupt.

#### II. Adoption

A `.md` file authored outside Pommora opens untouched. A missing `id` is synthesized from a hash of the file's Nexus-relative path, stable across launches, and missing timestamps fall back to the file's own. The loader never writes back — frontmatter is authored only when the user edits and saves — so opening a folder that's also an Obsidian vault leaves notes byte-identical until touched.

### Pending

**Properties Panel:** A property panel on the Page to view and edit the schema's property values. The data layer is complete; the surface isn't built.

**Compact Preview Window:** A lightweight preview card for Pages in a `compact` Collection (`open_in`). The routing is unwired, so Pages open in the main pane.

**Columns Directive:** The `Columns` multi-column section directive. Callouts already render in the editor (→ `MarkdownPM.md`); Columns isn't built.

### Prospects

**Sub-Pages:** A nested Page hierarchy — a Page owning child Pages — beyond the current flat Page-in-container model.

**Independent UI Titles:** A display title distinct from the filename, so a rename needn't move the file.

**Ad-Hoc Properties:** Page-local frontmatter fields outside the Collection schema.
