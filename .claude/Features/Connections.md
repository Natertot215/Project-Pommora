## Connections

A **Connection** is an inline `[[Title]]` link in a Page's Markdown **body** that points to another Page (Obsidian-compatible). `[[` is the **sole** connection syntax.

Connections are Pommora's in-prose linking mechanism, distinct from context-link properties (the `tier1` / `tier2` / `tier3` frontmatter values that bind entities to Contexts).

Related: [[Pages]] · [[PageEditor]] · [[Properties]] (context-link properties — the frontmatter counterpart) · [[Architecture]] (portability).

---

### Core principle — Pommora-owned, engine-independent

The Connection **system is Pommora's own code**: the grammar, the parser, the resolver, the link index, navigation, and cascade all live in Pommora. The Markdown editor is a **display + input surface only** — Pommora and the editor agree on the *same* grammar, but Pommora never asks the editor what a link means. If the editor is ever replaced, the grammar, resolution, index, navigation, and graph data survive; only a thin render/input adapter is rewritten.

---

### Scope

`[[Title]]` targets a **Page**; the source is any Page body.

**Not connection targets:** Contexts (Areas / Topics / Projects) are reached only through tier relations, never inline. Tasks / Events are excluded (a future "Tasks" / "Events" property mechanism covers them).

**Authored in Markdown bodies only.** Context and Homepage block surfaces (JSON, not Markdown) are not connection sources — inline connections inside composed-block surfaces are deferred.

`{{Title}}` is **not** a syntax — Pommora gives it no meaning, and the editor renders it as ordinary plain text.

---

### Identity — title only

- Connections resolve **by title**. Page titles are **globally unique** across the whole nexus, so a bare title is an unambiguous reference.
- On disk a connection is **just the bracketed title** — `[[Title]]`. No piped form, no embedded id, no alias.
- Resolution is `title → the unique target Page → that Page's own ULID`. The target's identity is its existing frontmatter `id`; the connection itself never carries one.

> **Why ban duplicates.** Title-only on disk is what keeps `[[ ]]` links readable as ordinary Obsidian wikilinks. Global uniqueness makes a bare title an unambiguous reference. Aliases and id-scoping for duplicate titles are deferred; when they land, duplicates become tolerable and the id rides in the index, not the body.

Uniqueness is enforced nexus-wide at create / rename: naming a Page a title any other Page already holds is rejected. Duplicates can therefore only *pre-exist* via adoption of an external nexus — never created in Pommora. While a duplicate persists, a connection to that title is ambiguous and stays unresolved until one side is renamed; surfacing the candidates for in-line selection rides with the deferred id-scoping work.

---

### No frontmatter mirror — body + index only

A Connection exists in exactly two places:

1. **The body** (`[[ ]]`) — canonical, human- and Obsidian-readable.
2. **The SQLite index** — a derived edge record, rebuilt by scanning bodies.

There is **no frontmatter mirror** of a file's links. A `wikilinks:` / `connections:` frontmatter array would only duplicate what the body already states; the body is the single source of truth, and the index regenerates from it. Identity safety across renames comes from cascade, not a stored id.

---

### Rename cascade

Because identity is the title and the body carries no id, **a rename cascades**: renaming a target rewrites every body that references its old title to the new title, across the nexus. Cascade is **mandatory** and **atomic** — on any write failure the whole rename rolls back. The index (which records who links whom) drives it; it is targeted, not a full scan.

> **Accepted tradeoff.** With no id in the body, cascade is the only thing preserving a link across a rename. A rename done *outside* Pommora (Finder, or Obsidian) that bypasses cascade orphans inbound links. The file watcher reconciles external renames where it can.

---

### Resolution + lifecycle

**Live visibility (non-negotiable).** A connection created or removed *inside Pommora* is reflected immediately on every user-facing surface — the editor, graph view, and any future connections panel or query — with no relaunch and no manual refresh. It registers the moment it resolves (its target exists) and deactivates the moment its target is gone. (A connection created or removed by an *external* tool reflects once Pommora sees the file — the file-watcher's job, [[Architecture]] "File-watcher".)

- **Resolved** — the title matches an existing Page → the connection is live (rendered + navigable).
- **Unresolved** — the title matches nothing → the connection renders as **plain prose with the brackets visible** (`[[Foo]]` shown literally) and is inert. No muted styling, no navigation.
- **Activation is automatic** — an unresolved connection goes live the moment a matching Page exists; a phantom edge recorded by normalized title makes this immediate.
- **Deletion deactivates** — permanently deleting a target reverts its inbound connections to inert plain text.
- **Trash is reversible** — moving a target to the trash makes it unreachable, so its inbound connections deactivate (inert) while it sits there. Restoring it re-scans and reactivates them — subject to the live uniqueness check, so a restore whose title was taken meanwhile prompts a rename first.
- **Connections never create entities** — typing `[[NewName]]` does not make a Page (it can't know where the Page belongs); the text stays inert until that Page exists.
- **Self-connections are not allowed** — a Page can't link itself.

Title matching — for both uniqueness enforcement and connection resolution — uses one shared normalization (trimmed, case-insensitive) so the two never disagree.

---

### Rendering

A resolved `[[ ]]` renders as **styled colored inline text** (Obsidian-style hyperlink) in the prose flow — never a pill or chip. Single-click navigates (opens the Page in the detail pane). Unresolved connections render as inert literal text (brackets visible). Page preview-on-click is deferred — navigation-first.

---

### Autocomplete

Typing `[[` opens a small search-filter popup above the caret listing Pages nexus-wide. Selecting inserts the title. A convenience, not load-bearing: a bare typed title resolves the same way.

---

### Index + graph data

The **body is the sole source of truth** — a connection exists because `[[ ]]` sits in the text. SQLite holds only a **derived, regeneratable index**, rebuilt by scanning bodies; it is never authoritative, and discarding it loses nothing the bodies don't already hold.

Connections live in their own index table, **separate** from the tier-relation store. Each connection is **one directed edge** keyed by source, target, the target's normalized title, multiplicity, weight, and a resolved flag (full schema → `PommoraPRD.md`). Connections are page-only; discriminator columns keep per-type weighting and filtering possible later.

- **Live updates, no relaunch** — every in-app create / edit / delete / rename updates the index in the same operation as the file write, so links, backlinks, and the graph reflect the change immediately. The full body-scan is only the cold-start bootstrap (and the rebuild-from-scratch recovery path); changes made outside Pommora reconcile via the file watcher while running, and via the scan on next launch.
- **One edge, both directions** — outgoing reads source, incoming / backlinks reads target. The same rows queried in reverse — there is no separate "incoming" store; an index on the target keeps the reverse query cheap.
- **Resolved + phantom** — unresolved connections are recorded by normalized title (no resolved target yet) so they activate when the title appears.
- **Multiplicity** — repeated links from one source to the same target increment a counter (the natural seed for graph weight).
- **Both directions captured for every Page**, so a future backlinks / connections panel reads them straight from the index. The display surface itself is deferred.

#### Weights

Per-edge weight is carried so per-edge-type weighting is **possible**; v1 ships uniform weight and no tuning UI. It is the escape hatch — if tier edges ever bury the idea-to-idea web in a node-graph, they can be down-weighted at query time. Carried, not used.

---

### Obsidian compatibility

`[[ ]]` links stay plain Obsidian wikilinks — title-only + globally unique → they resolve by filename in Obsidian and GitHub. Compatibility is a constraint on the disk format, not a coupling.

---

### Editor

The Markdown engine is the render + input surface; Pommora supplies all link semantics. The engine handles `[[ ]]` through a thin adapter; replacing the engine touches only that adapter.

---

### Deferred

Aliases · id-scoping for duplicate titles (with in-line candidate selection) · the backlinks / connections **display panel** (edge data captured now) · Page preview-on-click · connections inside Context / Homepage composed-block surfaces · Tasks / Events as connection targets · heading / block anchors (`#`, `#^`) · transclusion (`![[ ]]`).
