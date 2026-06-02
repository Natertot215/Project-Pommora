## Wikilinks

A wikilink is an inline `[[Title]]` reference in a Page's Markdown **body** that points to another Page. It's Pommora's in-prose linking mechanism — distinct from [[Properties|relations]] (which are frontmatter property values). This spec defines **what** wikilinks must be; implementation sequencing is deliberately out of scope (decisions are still settling in a parallel track).

Related: [[Pages]] (body + on-disk shape) · [[PageEditor]] (editor surface) · [[Architecture]] (portability) · [[Properties]] (relations, the frontmatter counterpart).

---

### Core principle — Pommora-owned, engine-independent

The wikilink **system is Pommora's own code**: the grammar, the parser that reads it, the resolver that gives a link meaning, the link index, and navigation all live in Pommora. The Markdown editor is a **display + input surface only**.

> **Compatibility, not dependency.** Pommora and the editor agree on the *same* link grammar, but Pommora does **not** depend on the editor to understand its own links — it has its own parser and resolver. If the editor is ever replaced (the React/Electron contingency, or any future swap), the wikilink grammar, resolution, index, navigation, and graph data survive untouched; only a thin render/input adapter is rewritten.

This mirrors how **relations** already work: an app-owned, ID-based linking system the editor knows nothing about. Wikilinks are the same kind of citizen — body-level instead of property-level.

---

### Identity model — Title + UID

Every wikilink pairs two things:

- **Title** — the human-readable label the user sees and types.
- **UID** — a stable identity (ULID) for the target Page that never changes, even when the Page is renamed.

The **UID is the source of truth for identity**; the Title is display. Cross-references resolve by UID-backed identity through Pommora's resolver, so a rename never severs a link. The Title↔UID mapping is owned and maintained by Pommora (not the editor, not the file alone).

The on-disk serialization must keep files **readable as ordinary Obsidian wikilinks** (see Obsidian compatibility below). How the UID is associated with the on-disk Title — and the exact on-disk form — is being finalized in the parallel decision track; the firm requirement is that identity is UID-based and resolution is Pommora-owned.

---

### Own resolver

Pommora resolves wikilinks through **its own resolver**, backed by its own index — never by asking the editor "what does this link mean."

The resolver answers:
- **Existence** — does a Page for this Title exist? (drives live vs. muted rendering)
- **Target identity** — which Page (UID) this link points at (drives navigation + the link graph)
- **Current display** — the target's up-to-date Title/icon, so renames reflect automatically

The resolver is the single seam the editor consults for styling; everything semantic about a link is decided here, in Pommora.

---

### Obsidian compatibility (≠ sameness)

Pages are files; a Pommora nexus opened in Obsidian must read cleanly. So:

- Wikilinks on disk stay **plain Obsidian-style `[[…]]`** — they render and resolve in Obsidian, GitHub, and any wikilink-aware tool.
- Pommora **mirrors Obsidian's helpful behaviors** (notably: auto-updating links across the vault when a Page is renamed) — but implements them itself, depending on neither Obsidian nor the editor.
- Where Pommora is *better* than Obsidian (UID-based identity → rename-safety beyond filename matching), that strength must never come at the cost of the file being unreadable in Obsidian.

**Compatibility is a constraint, not a coupling:** behave like Obsidian on disk; owe nothing to it in code.

---

### Reference — how Obsidian handles wikilinks

Captured so Pommora's choices are deliberate, not accidental:

- **Resolution by filename** — no extension, case-insensitive; on ambiguity, the shortest distinguishing path / folder prefix (`[[Folder/Note]]`).
- **Link forms** — `[[Note]]`, alias `[[Note|Display]]`, heading `[[Note#Heading]]`, block `[[Note#^id]]`, transclusion `![[Note]]`.
- **Metadata cache** — Obsidian maintains an index of `resolvedLinks` and `unresolvedLinks` (directed `source → {target: count}` maps); **backlinks are derived by inverting it**, and the **graph view reads it directly** (resolved targets are nodes; unresolved targets become "phantom" nodes).
- **Rename auto-update** — a setting ("Automatically update internal links") rewrites references across every linking note on rename, then refreshes the cache.

Pommora adopts the *shape* of this model (a directed-edge index with resolved + phantom edges and multiplicity, backlinks by inversion, rename rewrite) while keeping identity UID-based rather than filename-based.

---

### What the editor provides (that we build on, without depending on)

The vendored Markdown engine already ships a wikilink **display/input layer** Pommora can drive as an adapter:

- Renders `[[…]]` as styled inline text (live vs. broken), with bracket auto-pairing and caret ergonomics.
- Fires events on link **click** and on the caret entering/leaving a link (the hook an autocomplete UI rides on), plus a channel to push a chosen completion back in.
- Exposes a **resolver protocol** the host implements — the engine asks "does this exist?" and accepts Pommora's answer; it owns no link meaning.

Pommora uses these as the **render + input surface** and supplies all semantics. The engine understanding the same grammar is convenience, not dependency — Pommora's own parser is the source of truth for indexing and rewriting. Replacing the engine touches only this adapter.

---

### Link index + graph data

Every body wikilink is recorded as a **directed edge** (`source Page → target`) in Pommora's own index, **kept separate from relations** (relations are frontmatter properties; wikilinks are body prose — two distinct mechanisms, two distinct stores).

The index must capture, from day one, enough for a future graph:
- **Resolved and unresolved (phantom)** edges — a link to a not-yet-existing or deleted Page is still a recorded edge (a phantom node).
- **Multiplicity** — how many times a source links a target (the natural seed for graph **weights**).
- **Bidirectional queryability** — backlinks are the inverse query; no second store.

No backlinks panel and no graph view are built now. The **requirement** is that wikilink data is fully *expressible graphically*: a future node-graph will combine wikilinks **+** relations **+** container (vault/collection) membership with weights, and the wikilink edges must already be there to pull from.

---

### Behavior

- **Creation** — links are made to **existing** Pages (via an autocomplete picker over Pages). Typing or pasting a bare Title is also valid.
- **Links never create Pages.** Clicking a link to an existing Page opens it. An **unresolved** link — its target was deleted, or a Title typed ahead of the Page existing — renders **muted and is inert** (no navigation, no page creation); it resolves automatically once a matching Page exists.
- **Duplicate Titles** are allowed across different containers (uniqueness is per-container). Resolution is **duplicate-tolerant**: prefer a match in the linking Page's own container, otherwise a deterministic pick. Showing the target's vault/collection is the intended disambiguation lever if duplicates ever become a problem.
- **Rename auto-updates links** across every linking Page (Obsidian parity), driven by Pommora's link index — targeted, not a full scan. Rewrites stay safe in the presence of duplicate Titles.
- **Display** — wikilinks render as styled colored inline text (Obsidian-style hyperlink), in the prose flow — never as a chip/pill (chips are the relation visual).

---

### Wikilinks vs relations

| | Where it lives | What it links | How it renders |
|---|---|---|---|
| **Wikilink** | inline in the Markdown **body** | one Page → another Page (in prose) | styled colored inline text |
| **Relation** | a **frontmatter** property value | typed property → target entities (by ID) | the target's icon + Title (chip-free styled text), in the property surface |

Both resolve by stable identity and are rename-safe, but they are separate systems on separate surfaces — a wikilink never appears in the property surface, a relation value never appears inline in the body.

---

### Deferred (not part of the first wikilink scope)

Backlinks **panel** UI · graph **view** UI (the edge *data* is captured now) · heading/block anchors (`#`, `#^`) · transclusion (`![[…]]`) · wikilinks targeting non-Page entities (Items, Contexts).
