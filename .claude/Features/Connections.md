## Connections

A **Connection** is an inline link in an entity's Markdown **body** that points from one operational entity to another. Two syntaxes, scoped by **target kind**:

- `[[Title]]` → targets a **Page** (Obsidian-compatible).
- `{{Title}}` → targets an **Item** (Pommora-only).

Both are Connections — Pommora's in-prose linking mechanism, distinct from context-link properties (the `tier1` / `tier2` / `tier3` frontmatter values that bind entities to Contexts). "Wikilink" was the page-only forerunner; Connections generalize it to Pages **and** Items. This spec defines **what** Connections are and how they behave; implementation sequencing is out of scope.

Related: [[Pages]] · [[Items]] · [[PageEditor]] · [[Properties]] (context-link properties — the frontmatter counterpart) · [[Architecture]] (portability).

---

### Core principle — Pommora-owned, engine-independent

The Connection **system is Pommora's own code**: the grammar, the parser, the resolver, the link index, navigation, and cascade all live in Pommora. The Markdown editor is a **display + input surface only** — Pommora and the editor agree on the *same* grammar, but Pommora never asks the editor what a link means. If the editor is ever replaced, the grammar, resolution, index, navigation, and graph data survive; only a thin render/input adapter is rewritten.

---

### Scope — by target, not surface

The bracket type names the **target's kind**, independent of which body the connection is typed in:

| Syntax | Targets | Source may be |
|---|---|---|
| `[[Title]]` | a **Page** | any Page or Item body |
| `{{Title}}` | an **Item** | any Page or Item body |

All four directions are in scope: page→page, page→item, item→page, item→item. `[[` always resolves to a Page, `{{` always to an Item — so a Page and an Item that share a title are never ambiguous.

**Not connection targets:** Contexts (Spaces / Topics / Projects) are reached only through tier relations, never inline. Agenda Tasks / Events are excluded in v1 (a future "Tasks" / "Events" property mechanism will cover them).

**Authored in Markdown bodies only.** Connections live in Page and Item bodies. Context and Homepage block surfaces (JSON, not Markdown) are not connection sources in v1 — inline connections inside composed-block surfaces are deferred.

---

### Identity — title only

- Connections resolve **by title**. Titles are **globally unique per kind**: every Page title is unique across the whole nexus, every Item title is unique across the whole nexus. A Page and an Item **may** share a title (the syntax disambiguates).
- On disk a connection is **just the bracketed title** — `[[Title]]` / `{{Title}}`. No piped form, no embedded id, no alias.
- Resolution is `title → the unique target entity → that entity's own ULID`. The target's identity is its existing frontmatter `id`; the connection itself never carries one.

> **Why ban duplicates.** Title-only on disk is what keeps `[[ ]]` Page links readable as ordinary Obsidian wikilinks. Global uniqueness makes a bare title an unambiguous reference. Aliases and id-scoping for duplicate titles are deferred (post-v1); when they land, duplicates become tolerable and the id rides in the index, not the body.

Uniqueness is enforced at create / rename: naming a Page a title any other Page already holds (nexus-wide) is rejected; same for Items. (Today `NameCollisionValidator` enforces this per-container; Connections widen it to per-kind nexus-wide.) Duplicates can therefore only *pre-exist* via adoption of an external nexus — never created in Pommora. While a duplicate persists, a connection to that title is ambiguous and stays unresolved until one side is renamed; surfacing the candidates for in-line selection (backed by the ID index) rides with the post-v1 id-scoping work.

---

### No frontmatter mirror — body + index only

A Connection exists in exactly two places:

1. **The body** (`[[ ]]` / `{{ }}`) — canonical, human- and Obsidian-readable.
2. **The SQLite index** — a derived edge record, rebuilt by scanning bodies.

There is **no frontmatter mirror** of a file's links. A `wikilinks:` / `connections:` frontmatter array would only duplicate what the body already states; the body is the single source of truth, and the index regenerates from it. Identity safety across renames comes from cascade, not a stored id.

---

### Rename cascade

Because identity is the title and the body carries no id, **a rename cascades**: renaming a target rewrites every body that references its old title to the new title, across the nexus. Cascade is **mandatory** and **atomic** — on any write failure the whole rename rolls back. The index (which records who links whom) drives it; it is targeted, not a full scan.

> **Accepted tradeoff.** With no id in the body, cascade is the only thing preserving a link across a rename. A rename done *outside* Pommora (Finder, or Obsidian for `[[ ]]`) that bypasses cascade orphans inbound links — most acute for `{{ }}` item links, which Obsidian can't auto-update. The file watcher reconciles external renames where it can.

---

### Resolution + lifecycle

**Live visibility (non-negotiable).** A connection created or removed *inside Pommora* is reflected immediately on every user-facing surface — the editor, graph view, and any future connections panel or query — with no relaunch and no manual refresh. It registers the moment it resolves (its target exists) and deactivates the moment its target is gone. (A connection created or removed by an *external* tool reflects once Pommora sees the file — the file-watcher's job, [[Architecture]] § "File-watcher contract".) *How* the index and open views stay in lockstep is left to the plan.

- **Resolved** — the title matches an existing target → the connection is live (rendered + navigable).
- **Unresolved** — the title matches nothing → the connection renders as **plain prose with the brackets visible** (`[[Foo]]` / `{{Foo}}` shown literally) and is inert. No muted styling, no navigation.
- **Activation is automatic** — an unresolved connection goes live the moment a matching entity exists; a phantom edge recorded by normalized title makes this immediate.
- **Deletion deactivates** — permanently deleting a target reverts its inbound connections to inert plain text.
- **Trash is reversible** — moving a target to the trash makes it unreachable, so its inbound connections deactivate (inert) while it sits there. Restoring it re-scans and reactivates them — subject to the live uniqueness check, so a restore whose title was taken meanwhile prompts a rename first.
- **Connections never create entities** — typing `[[NewName]]` does not make a Page (it can't know where the Page belongs); the text stays inert until that entity exists.
- **Self-connections are not allowed** — a Page can't link itself; an Item can't link itself.

Title matching — for both uniqueness enforcement and connection resolution — uses one shared normalization (trimmed, case-insensitive) so the two never disagree.

---

### Rendering

| | Resolved render | Single-click | Double-click |
|---|---|---|---|
| **Page `[[ ]]`** | styled colored inline text (Obsidian-style hyperlink), in the prose flow — never a pill | navigates (opens the Page in the detail pane) | — |
| **Item `{{ }}`** | an **Item Chip** (icon + title; the item-side parallel to `ContextChip`) | opens an inline dropdown previewing the item's body text | opens the **Item Window** (floating panel) |

Unresolved connections of either kind render as inert literal text (brackets visible). Page preview-on-click is deferred — navigation-first now. **Right-clicking an item connection** offers **"Open '\<title\>'"**, which opens the Item Window directly (bypassing the dropdown). The Item Chip and its dropdown are designed in Figma.

> Item connections render as a chip (icon + title) precisely so they read differently from Page links (plain colored text) at a glance — the two-syntax design made visible. A chip here means the icon+title primitive (as with `ContextChip`), not a boxed Notion pill.

---

### Autocomplete

Typing `[[` or `{{` opens a small search-filter popup above the caret — Pages for `[[`, Items for `{{`, nexus-wide. Selecting inserts the title. A convenience, not load-bearing: a bare typed title resolves the same way.

---

### Index + graph data

The **body is the sole source of truth** — a connection exists because `[[ ]]` / `{{ }}` sits in the text. SQLite holds only a **derived, regeneratable index**, rebuilt by scanning bodies; it is never authoritative, and discarding it loses nothing the bodies don't already hold.

Connections are recorded in a single **`connections`** table — one table with discriminators, kept **separate** from `context_links` (the tier-relation store). Each connection is **one directed edge**:

`(id, source_id, source_kind, target_id, target_kind, surface, multiplicity, weight, resolved, modified_at)`

- **Live updates, no relaunch** — every in-app create / edit / delete / rename updates the index in the same operation as the file write, so links, backlinks, and the graph reflect the change immediately. The full body-scan is only the cold-start bootstrap (and the rebuild-from-scratch recovery path); changes made outside Pommora reconcile via the file watcher while running, and via the scan on next launch.
- **One edge, both directions** — outgoing = `source_id = ?`; incoming / backlinks = `target_id = ?`. The same rows queried in reverse — there is no separate "incoming" store. (The pattern `IndexQuery.incomingContextLinks` already uses for contexts; the `target_id` index keeps the reverse query cheap.)
- **Resolved + phantom** — unresolved connections are recorded by normalized title (no `target_id` yet) so they activate when the title appears.
- **Multiplicity** — repeated links from one source to the same target increment a counter (the natural seed for graph weight).
- **Both directions captured for every Page and Item**, so a future surfacing (a backlinks / connections panel) reads them straight from the index. The display surface itself is deferred.

A single unified table (not per-shape tables) keeps one indexer + query path, while the `source_kind` / `target_kind` columns still allow per-type weighting and filtering later.

#### Weights

The `weight` column exists so per-edge-type weighting is **possible**; v1 ships uniform weight and no tuning UI. In a node-graph, size follows degree — Contexts naturally accumulate the most edges and read as the largest cores, which is correct, not a distortion. Weight is the escape hatch: if the organizational skeleton ever buries the associative web, tier edges can be down-weighted at query time to surface idea-to-idea links. Carried, not used.

---

### Obsidian compatibility (Pages only)

- Page `[[ ]]` links stay plain Obsidian wikilinks — title-only + globally unique → they resolve by filename in Obsidian and GitHub.
- Item `{{ }}` is Pommora-only; Obsidian renders it as literal text. Accepted — Items aren't fully Obsidian-native entities, and Pommora is its own product.
- Where a Page and an Item share a title, Obsidian sees two same-named `.md` files and resolves `[[Title]]` by its own heuristic; this affects only the Obsidian view, never Pommora's syntax-disambiguated resolution.

Compatibility is a constraint on the Page-link disk format, not a coupling.

---

### Editor (MarkdownPM)

The Markdown engine is the render + input surface; Pommora supplies all link semantics. The engine already handles `[[ ]]` (`WikiLinkService`). Connections add a `{{ }}` tokenizer + styler and the **Item Chip** widget (its dropdown + double-click-to-window affordance). Replacing the engine touches only this adapter.

---

### Deferred (post-v1)

Aliases · id-scoping for duplicate titles (with in-line candidate selection) · the backlinks / connections **display panel** (edge data captured now) · Page preview-on-click · connections inside Context / Homepage composed-block surfaces · Agenda entities as connection targets · heading / block anchors (`#`, `#^`) · transclusion (`![[ ]]`).
