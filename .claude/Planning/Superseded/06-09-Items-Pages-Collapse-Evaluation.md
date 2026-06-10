## Items + Pages Collapse — Evaluation (Decision-Support, NOT a Plan)

This document records a grounded evaluation of a proposal to collapse Items and Pages into one entity. It is **decision-support, not an implementation plan** — nothing here is committed, and the proposal as originally framed is **not** the recommended path. A 6-agent fleet grounded every claim in `graphify-out`, the live Swift sources, the `// Features//` specs, and external prior art.

### The proposal evaluated

Collapse Items + Pages into **one entity**: one Type concept, one manager, one folder model; drop the non-authoritative `Class: item|page` stamp; delete the duplicated `Item*`/`Page*` parallel system. The class distinction becomes **per-vault Layout settings** — open-in default (Preview = a bounded-to-Pommora WindowGroup, promotable to full detail; vs Page = main detail pane) plus a templates toggle. **No body cap** (the body scrolls inside a smaller bounded window). Sequenced as: full migration first, pinned-property zones rebuilt cleanly afterward. Downstream-only (noted, not decided): chips-vs-links rendering, 3-level org (Vault › Collection › Set), and a "Vault" rename.

### The core finding: three separable wins, bundled as one

The proposal conflates three independent wins and pays full migration cost to get all three:

1. **Code dedup** — ~2,000–2,400 LOC of duplicated `Item*`/`Page*` manager/type/collection mirrors.
2. **UX fluidity** — a thing can open in a window *or* full-frame.
3. **Conceptual "one entity"** — drop the `Class` stamp + the cap, merge the data.

Wins #1 and #2 are real and valuable. **Win #3 is the only one that requires the destructive moves, and it carries the lowest user-visible payoff and nearly all the risk.** They are separable.

### Grounded facts (agent consensus)

- **The on-disk format is already unified.** Both forms are `.md` (frontmatter + body) on one `AtomicYAMLMarkdown` codec. `Content//KindStamp.swift` documents the split as *"two forms of one entity-type."* This is not a merge of two formats.
- **The duplication is real but lives in thin orchestration wrappers** — `ItemTypeManager`/`PageTypeManager`, the two CRUD managers, `ItemCollection`/`PageCollection`, four byte-identical validators. The load-bearing algorithms beneath them (`SchemaTransaction`, `ConnectionCascade`, `NameCollisionValidator`, `EntityContainer`) are **already single-sourced**.
- **The asymmetry is also real, and a merge relocates rather than deletes it.** Three things have no Page twin: the entire `ItemWindow//` subsystem (~1,100–2,000 LOC; Pages use the TextKit-2 detail-pane editor instead), the body cap (`ItemValidator.maxDescriptionLength`, Items-only), and the template/pinned-property machinery (`PageTemplateConfig` is an empty parity stub). `Item` holds its body in memory; `PageMeta` is a deliberately thin, lazy handle because page bodies are unbounded.

### The six lenses

- **Uniqueness — sharpens (high confidence).** Pommora's three load-bearing constraints never reference the Items/Pages split. Every competitor on the same axis (Anytype, Tana, Capacities) collapsed it; Notion — the lone holdout — is criticized *for* keeping it. The split is incidental scaffolding, not the paradigm.
- **Sustainability — net simplification, medium risk.** ~2,000–2,400 LOC deletes. Enum-not-sprawl risk is low (`LayoutArchetype`/`OpenInMode` enums already exist). Migration is lighter than feared: Item Types and Page Types are already flat siblings (no folder moves), and the SQLite index is regeneratable. Risk concentrates in migration + timing.
- **Feel vs Function — argues against the destructive version.** `// Features//Properties.md` states *"the cap, not the format, distinguishes an Item from a Page."* Removing it makes the atomic feel *conditional* (holds only while the body stays short); a promotable bounded preview cannot deliver document-immersion *at rest*. Recommends unifying the substrate (already done) while keeping the interaction model opinionated.
- **For — strong.** One entity wearing two coats; 80–94% line-identical. Advances Pommora's own HARD RULES (DRY, simplicity-first) and Core Principles (files-canonical, agent-legibility). Notion's data model is the existence proof.
- **Against — strong, and decisive on timing.** Symmetric *naming* ≠ symmetric *behavior*. The asymmetric core (Item Window, cap, templates) gets relocated into runtime conditionals — the configurable-supertype / god-object anti-pattern (Palantir ontology guidance: model shared traits via interfaces, keep distinct types). Dropping `Class` removes the only per-file form record, weakening agent-legibility and portability. Folder/schema collapse is anti-additive against the cloud-sync constraint.
- **Alternatives — recommends a cheaper lever.** A generic core + two thin facades captures ~85% of the dedup at **zero data-migration risk**. View-mode fluidity is already the queued `PreviewWindow` primitive. Prior art (Anytype) validates *"uniform storage + a cheap form discriminator"* — which Pommora already has — not a total merge.

### Why the destructive moves cost the most

- **Dropping `Class`** removes the only per-file record of form. An externally-edited or homeless `.md` no longer self-classifies — directly weakening two of the three load-bearing constraints (*agent-legibility*, *conceptual portability*).
- **Removing the cap** deletes the documented distinction-bearer and turns the atomic "record" feel from inherent into conditional.

### Recommendation

Capture wins #1 and #2; skip the costly version of #3.

1. **Unify the duplicated machinery via a generic core / shared protocol, keeping Item and Page as two thin *forms* of one codec.** ~85% of the code deletion at zero data-migration risk — no `Class` removal, no folder moves, no schema collapse. This is the Anytype model (uniform storage + cheap form discriminator), which Pommora already approximates.
2. **Let open-mode become fluid through the `PreviewWindow` primitive** — the surface the parallel session is already building toward. Delivers "a Page can open in a window; an item can go full-frame" without merging the data model.
3. **Keep the cap as a per-vault *soft default*, not a hard rule** — preserves scroll-free-at-rest atomicity while allowing overflow, which is most of what "no cap" was reaching for.

### Timing (unanimous, including the pro-merge lenses)

Touch none of this until **ItemsV2 (Phases E/F) is green** and the **`NSPanel → WindowGroup` migration has settled**. Evaluating a foundational change against two moving surfaces produces an answer that is wrong the moment it is written. Matches the "not this session" framing.

### Decision (recorded 2026-06-09)

**Direction chosen: full collapse (option B), with a clarified surface model.** One entity. A **single shared `PagePreview` surface used by everything** — not `ItemWindow` plus a separate page surface. The sole per-vault setting is how a page opens (Compact preview window vs Window/full detail pane). No hard body cap. **Pinned properties were dropped** (a default-open inspector covers the use case — recorded as a Prospect). This overrides the recommended generic-core path; the evaluation above was presented in full before the decision. Implementation spec: `06-09-Items-Strip-Spec.md`.

**Risks accepted with eyes open (carry into the eventual plan, do not re-debate):**

- **`Class` stamp removal vs agent-legibility/portability.** With one entity the per-file form record goes away. The plan must define how an externally-edited or homeless `.md` still self-classifies (folder-sidecar authority must carry the full weight the `Class` cross-check used to share).
- **Cap removal vs felt atomicity.** The preview must preserve a scroll-free-*at-rest* feel (e.g. a per-vault soft default / visual truncation) so a record-shaped vault still *feels* atomic rather than like a cramped document.
- **Single `PagePreview` must not become a god-object.** Per-vault behavior belongs in finite enums + `switch` (extend `LayoutArchetype` / `OpenInMode`), never `if isItem`/loose-flag branching — per the HARD RULES.

**Timing gate (unchanged, unanimous):** not this session. Begins only after ItemsV2 (Phases E/F) is green and the `NSPanel → WindowGroup` migration has settled. The parallel session continues oblivious; the eventual plan builds on whatever window primitive it lands.

Next step when the gate clears: brainstorm → spec → plan the migration (data: `Class` removal + sidecar collapse + index schema merge; code: manager/type/collection unification; UX: the shared `PagePreview` + per-vault Layout settings; then pinned-property zones on the clean slate).
