## PropertiesV2 (Nexus-Wide Properties) — Decision Log

> Status: **V2 — review round 1 folded** (studio-brainstorm discipline). Living log — decisions tagged `[confirmed] / [assumed] / [open]`. Round 1 = fresh-eyes self-review + three independent adversarial agents (compile-grounding · logic/coverage · over-engineering) run against the real code. The build stage is written from this.

> **Round-1 changelog (V1 → V2):** cross-process seam resolved (main resolves `assignments→defs` in `readNexus`; `assigners` is a main-side sidecar scan) · assignment list is a **flat `prop_<ulid>` string array** (Nathan's call; local-props migrate via a format bump) · optimistic propagation bus **deferred** (v1 = existing load-after-write; schema edits are low-frequency, not a hot path) · **Clear Values cut** (model is Remove + Delete only) · archive-on-delete kept but as a **timestamped JSON snapshot in the trash convention** · stale migration bullets deleted (F-1 clean-wipe dissolved them) · corrections: `refreshSessionIndex` fires **14×**, `property_definitions` has **no FKs** (drop owner cols on a version bump), `colorMap.ts` also normalizes Notion/generic colors (keep it — remove only the Swift-accent read-map), "EventKit groups" → plain status groups · git-sync of a real vault is **out of scope** (Nathan) — registry stays `.nexus/properties.json`, synced-vs-per-machine split is deferred future-cloud-sync work.

### Frame

- **Purpose:** Flatten property *definitions* from per-Collection to **nexus-wide** — one shared registry (`.nexus/properties.json`) that Collections *assign* (validate) rather than each holding its own definitions.
- **Core Value:** Create a property once, reuse it across Collections with a shared ID — unlocking cross-Collection queries, clean cross-Collection moves (adopt, don't strip), and the elimination of duplicate per-Collection definitions.
- **Success Criteria:** A property defined once is assignable to any Collection with the same ID; a cross-Collection query (`Priority = High`) matches pages across Collections; a page move adopts by assignment (never strips); existing page files need zero migration; the daily assign/unassign path never fans out across the Nexus.

### Sources

- [[PommoraPRD]] — constraint #2 "cross-nexus queryable" (§Three load-bearing constraints); "ad-hoc properties / multi-Collection pages" parked post-v1 (§v1 Scope, "Out"); Storage Philosophy (files canonical, agent-legible, index off the read path).
- [[Properties]] · [[Collections]] · [[Structure]] · [[Architecture]] · [[Agenda]] · [[Contexts]] · [[Views]] — the current per-Type schema model, identity (ID vs name), move semantics, the data layer.
- `shared/properties.ts` — `PropertyDefinition` (looseObject, snake_case on-disk), `PropertyType` union, `RESERVED_PROPERTY_ID`, `mintPropertyId` (`prop_<ulid>`).
- `shared/propertyValue.ts` — tagged `PropertyValue`, `parsePropertyValue` (shape-inferred, schema-free), `applyPropertyValue` (the sole set/clear owner, ID-keyed).
- `shared/schemas.ts` — `pageCollectionSidecar.properties` (the per-collection store), `agendaConfigSidecar.property_definitions`, `pageFrontmatter.properties: record(string, unknown)`.
- `main/crud/schema.ts` — the `SchemaTarget` generalization (`PAGE_TARGET` + `agendaTarget`); add/rename/reorder/delete/changeType; `SchemaTransaction` + `stageMemberStrips` (the one-folder member strip).
- `main/crud/page.ts` (`movePage` = pure rename) · `main/mutate.ts` (`movePage` case: no schema logic) · `main/crud/loadValues.ts` (schema-free value load) · `main/readNexus.ts:217` (`CollectionNode.properties` source) · `main/io/pageFile.ts` (`mergeFrontmatter` — foreign-key + comment preservation).
- `renderer/Detail/Views/pipeline/*` — `resolveView` takes `schema` as a plain param (source-agnostic); `value.ts` `declaredType`/`resolveFieldValue`.
- `renderer/Components/Detail/{ViewPane,PropertiesPane}.tsx` + `Detail/Scope.ts` — the ancestor-walk-to-owning-Collection for the schema editor.
- `main/index/{schema,build,upsert}.ts` — the SQLite `property_definitions` table (owner-keyed today; regeneratable).
- **Prior art** — Obsidian `.obsidian/types.json` (the Nexus is also an Obsidian vault): a flat *vault-wide* `name → coarse-type` registry (`Status: multitext`, `Areas: multitext`…), no assignment / validation / options, **name-keyed**. The nexus-wide instinct made real, at the maximally-loose end — the contrast that frames PropertiesV2 as Obsidian-global + Notion-validated + Pommora-ID-keyed.

### Decisions

#### A — Core Model

**A-1:** [confirmed] Definitions move to a single nexus-wide registry at **`.nexus/properties.json`**; page/agenda **values stay ID-keyed in frontmatter/JSON, unchanged**. Because values are already `prop_<ulid>`-keyed (nexus-stable) and the pipeline already takes `schema` as a plain parameter, **existing files need zero migration** — a `prop_<ulid>` means the same thing wherever its definition lives.

**A-2:** [confirmed] A page stays **confined to a single Collection** (folder = membership). Nothing here introduces multi-Collection pages or ad-hoc per-page properties — the model stays schema-based; only the *definitions* go nexus-wide.

**A-3:** [confirmed] A Collection's sidecar carries an **assignment list** — a flat `prop_<ulid>` string array (`properties: ["prop_…"]`, replacing the old `PropertyDefinition[]`) naming which nexus-wide props it validates, in place of holding definitions. A page validates/shows only the properties its Collection assigns. A Set inherits its Collection's assignment (as it inherits the schema today).

**A-4:** [confirmed] The nexus-wide benefit is **read-side** — cross-Collection *queries* (shared IDs make `Priority = High` match across Collections) and clean *moves* (a moved page's values reference nexus-wide defs, so the destination *assigns* them or the values ride through as foreign; never a schema strip). Never page multi-membership.

#### B — Definition Granularity

**B-1:** [confirmed] A nexus-wide property is **one definition and one value set, fully shared** across every Collection that assigns it — including a Select/Status's options. Cross-query coherence requires "High" to mean the same option everywhere. Genuinely divergent needs → a *separate* property ("Category" with its own values ≠ "Type"), not forked options under one ID.

#### C — Assign / Unassign / Edit / Delete  *(the core interaction + the one cost center)*

**C-1:** [confirmed] Three operations on a property's native context menu, separating the cheap reversible common op from the rare destructive ones:
- **Edit:** an *assigned* property shows a **`>` chevron** → the editing pane; editing changes the **global definition** (name/type/options) for every assigning Collection ("one definition" — no local edit). Schema-only (values ID-keyed, no cascade). An *unassigned* property shows a **`+`** (assign) instead — the chevron appears only once assigned.
- **Remove (unassign):** drops *this* Collection's reference only. Non-destructive + reversible — global def + other Collections untouched, and the pages' values **stay in frontmatter as foreign data** (re-assign restores them instantly). **No Nexus-wide fan-out.** The daily path.
- **Delete** (confirm-gated): remove the def *and* scrub its values across every assigning Collection. Fans out across all assigners — needs an `assigners(propId)` reverse lookup that doesn't exist today (`stageMemberStrips` is one-folder). *(V2: the "Clear Values" variant — scrub values, keep the def — was **cut**; the model is Remove + Delete. It returns as a Prospect only if a keep-schema-drop-data need appears.)*

**C-2:** [confirmed] A Delete is **recoverable, not lossy.** Before the scrub, one **timestamped JSON snapshot** — `{ propId, def, values: { pageId: value } }` — is written into the existing trash convention (`io/atomicWrite.ts` `trashWithTimestamp` location), NOT a bespoke nested `property→collection→page→value` tree (V2: that was over-built, cut). The live frontmatter is then **fully scrubbed** (not merely hidden) so a deleted property can't still match a cross-Nexus query; the snapshot is the recovery path. This resolves the fan-out's only real risk (data loss): the scrub is reversible from the snapshot.

#### D — Registry Scope

**D-1:** [confirmed] The registry serves **Pages / Collections only** for now. **Agenda (Tasks/Events) keep their own separate `property_definitions`** — unchanged. Rationale: Agenda isn't built yet (don't pull its rework into this scope), and merging the namespaces "flattens" a distinction a consumer may want — a *note* should be able to feel different from a *task*. Cross-type merging is possible later (Prospect), not now.

**D-2:** [confirmed] **Status** on a Collection is a nexus-wide registry property like any other — one shared definition (the fixed to-do / in-progress / done status *groups* + shared options per B-1), opt-in/assignable to a Collection. A future **Agenda feature keeps its entities' properties fully independent from content** (D-1) — Agenda's Status is its own. *(V2: "EventKit groups" was a Swift-era term — React owns the grouping.)*

**D-3:** [confirmed] **Tiers** (`_tier1/2/3`) unchanged — already effectively nexus-wide (synthesized from the global Contexts on read); they stop being a special-case against a per-collection schema. *Far-future, out of scope:* Contexts becoming user-creatable beyond the three fixed tiers — noted, not designed for, not foreclosed.

**D-4:** [confirmed] Values stay **`prop_<ulid>`-keyed under `properties`** — ID-keying kept (rename-safe; registry stays stable). Flat top-level OKF/Obsidian-native keys were **considered and deferred** (see Prospects); the final doc must record they were weighed.

#### E — Interaction & Propagation  *(how a change cascades Nexus-wide, fast)*

**E-1:** [confirmed-design] **Main is authoritative; the read path stays a single fs walk** (V2 — resolves the round-1 blocker that framed the registry as renderer in-memory maps while `CollectionNode.properties` is built in main). `readNexus` reads `.nexus/properties.json` (the registry) + each Collection sidecar's assignment array and **joins them to build `CollectionNode.properties`** in the same shape it has today — the renderer renders columns from that, never reading the registry directly for layout.
- `effectiveSchema(C) = assignments[C].map(id => registry[id]).filter(Boolean)` — the join `readNexus` runs; `.filter(Boolean)` drops a dangling ref (a def deleted but an assignment not yet reconciled).
- `assigners(propId): collectionId[]` — a **main-side scan** of Collection sidecar assignment arrays (main already walks the tree); scopes a broad op's fan-out. Net-new but cheap (few Collections).
- **Deferred (V2):** the renderer-store in-memory maps + optimistic-then-persist bus. v1 persists to disk then re-reads (the existing load-after-write schema CRUD already does this) — schema edits are low-frequency, so this is NOT an "on every X" hot-path violation. The optimistic layer is a later latency pass, not a correctness requirement. The store MAY cache registry + assignments to drive the assign UI's "+ unassigned" lists, but rendering correctness lives in main.

**E-2:** [confirmed-design] The cascade paths — each is *in-memory update → atomic disk write → re-render of only the open, affected views*:

| Op | Disk | Store | Propagates to |
|---|---|---|---|
| **Create** (in C) | registry += def; C sidecar += ref | `registry[id]=def; assignments[C]+=id` | C (new column) + every collection's "+ unassigned" list |
| **Assign (+)** (P→C) | C sidecar += ref (dedup: skip if already assigned) | `assignments[C]+=P` | C only |
| **Remove / unassign** (P from C) | C sidecar −= ref | `assignments[C]−=P` | C only — values stay in frontmatter, hidden, reversible |
| **Edit** (rename/type/options of P) | `registry[P]` updated | `registry[P]=def` | `assigners(P)` only |
| **Delete** (P) | snapshot → strip P everywhere + remove def + drop from every assignment | `delete registry[P]`; `assignments −= P`; values cleared | `assigners(P)` + every "+ list" |

**E-3:** [confirmed-design] **External edits** (an agent writes `.nexus/properties.json` directly — the OKF/agent-legibility path) reconcile **surgically**: the watcher re-reads the single registry file, updates the in-memory registry, re-renders affected surfaces — never a coarse full-Nexus rebuild.

**E-4:** [confirmed-design] Broad destructive ops (Clear/Delete) are **archive-first**, then one **atomic multi-file transaction** (the existing `SchemaTransaction`) across every assigner — all-or-nothing; a failure rolls back with nothing lost.

#### F — Migration & Write-Side Reconciliation  *(from the leftover hunt — code-grounded)*

**F-1:** [confirmed] **Clean slate — no migration.** Nathan: there is no valuable property data in either nexus (Test or The Nexus); wipe all existing Pommora properties and start V2 fresh. This dissolves the dedup tension entirely — the registry begins empty, no per-collection defs to collapse, no page values to re-key. The V2 "migration" is a one-time **wipe** of Pommora's property system (the `properties[]` schema on Collection sidecars + the `properties: {}` value object in page frontmatter), NOT a data migration. Scope guard: the wipe touches **only** Pommora's property surfaces — never the vault's Obsidian-native flat frontmatter (tags, top-level keys), the `tier1/2/3` context relations, page bodies, ids, or icons/covers.

**F-2:** [confirmed-correction] **There is no existing property-ID migration in React** — it was built ID-first from day one (values already `prop_<ulid>`-keyed). The Don't-Forget's "existing migration is the template" was wrong; the V2 sidecar migration (`properties[]` → registry + assignment) is written **fresh**. (Architecture.md's §Migration name→id pass is Swift-era, unbuilt here — reconcile that doc.)

**F-3:** [confirmed] **Validation splits by op.** Today's `validateName`/`validateDefinition` (uniqueness within *one* Collection's defs) must become: **Create** validates against the *whole registry*; **Assign (`+`)** runs **no** name-clash check (it's a reference, not a new def — else re-using an existing "Status" is wrongly rejected). The single most important write-side reconciliation.

**F-4:** [confirmed] **Global Edit / Clear / Delete fan out via `assigners(P)`.** Today `changeType`'s lossy value-strip and `deleteProp`'s strip run on **one folder's** members (`stageMemberStrips`); under a shared registry they must strip across **every** assigner or siblings keep stale-shaped values. Good news: `SchemaTransaction` is already **path-agnostic + all-or-nothing across any folders** — only its *caller* is one-folder-bound, so this is a caller change (enumerate `assigners(P)`'s pages), not new transaction infra.

**F-5:** [confirmed] **SQLite `property_definitions` — drop owner-scoping (latent bug today).** PK is `id` alone; under V2 the same `prop_<ulid>` assigned to N Collections would `INSERT OR REPLACE`-collide (only the last owner survives). The `owning_type_id/kind` columns are **not** FKs (V2 correction — no cascade; just unlinked scoping). Vestigial anyway — `assigners` is a main-side sidecar scan, not this table. Bump `SCHEMA_VERSION`, drop the owner columns; the index regenerates. Nothing on the read path depends on it.

**F-6:** [confirmed] **The one net-new read gate is the Inspector panel.** Every existing surface already gates through the schema (the invariant holds for free — the payoff of columns-from-schema + `declaredType`-pregating). The Inspector is an empty scaffold today and is *the* future per-page property-value surface — when built it must gate on the Collection's assignment. Also: `effectiveSchema(C)` must return the **same array shape** `CollectionNode.properties` gives today (raw user defs only — tiers stay pipeline-synthesized), so the tier-append logic stays correct; don't inject tiers into the registry.

### Core (must-have)

- The nexus-wide registry (`.nexus/properties.json`) + the Collection assignment list (A-1/A-3), fully-shared definitions (B-1), single-Collection pages (A-2).
- Assign / unassign / edit as the daily path; global-delete as the rare fan-out op (C-1).
- Zero page-file migration (A-1); the SQLite index drops owner-scoping on a version-bump rebuild.

#### Prospects (allowed later, not now)

- **Collection-exclusive (local) properties** — an assignment-list entry that's an *inline* def scoped to one Collection (vs a global reference). Default nexus-wide; local an opt-in "keep here only" flag. *V2 decision:* the assignment list is a **flat `prop_<ulid>` string array**, NOT pre-shaped for inline defs (Nathan's call — the earlier "design the shape now" instinct was YAGNI). When local-props ship, the shape migrates via a versioned-format bump (`["prop_x"]` → richer entries), which the zod-validated on-disk format already supports: cheap-later beats union-complexity-now for an unbuilt feature. Value: keeps the global registry clean + an escape hatch; cost: ViewPane must signal shared-vs-local, and a local-prop value rides through as foreign on a cross-Collection move.
- **Functional "unsorted" folders** — a catch-all Collection validating real nexus-wide properties instead of a dead bin (enabled by A-3).
- **"Max Properties" per-Collection allowance** — an optional cap on how many properties a Collection may assign (keeps a Collection focused; a guardrail). Could be useful; **not scoped now.** *Plan hook:* the implementation plan MUST **stop and ask Nathan about this when it becomes relevant** (i.e., when building the assignment surface) — never silently include or omit it.
- **Per-embed views (Notion-linked-DB style)** — an embedded block carrying its own view config that isn't a saved view of the source Collection. A *Views-layer* feature that nexus-wide IDs make queryable/cheap; enabled here, specced there.
- **Obsidian-native flat property keys** *(Nathan's "special-char / OpenKnowledge / visually-identical" idea, clarified by the Obsidian look)* — today values nest under `properties: { prop_<ulid>: v }`, which Obsidian's Properties UI sees as one opaque object. The prize: flat top-level frontmatter keys so a Pommora page reads as a native concept file in **OKF** (Google Cloud's Open Knowledge Format — a vendor-neutral markdown+frontmatter spec for agent knowledge, `type` required + flat optional metadata; the closest external standard to Pommora's own agent-legibility bet) and in Obsidian's Properties UI. The trade: OKF/Obsidian flat keys are **name-keyed** (legible, rename-unsafe); `prop_<ulid>` is rename-safe but opaque — a special char could mark "Pommora-managed" top-level keys, but this touches the deliberately schema-free by-shape value codec + the rename-safety guarantee. *Don't-foreclose:* keep values ID-keyed under `properties` in the core (D-4); treat OKF-flat legibility as its own design pass.

#### Out of Scope (won't do — distinct from Prospects)

- Multi-Collection page membership; ad-hoc per-page properties (both stay parked per the PRD).

#### Considered & Rejected

- **Status quo — per-Collection schemas (the Notion-per-database model).** The complete opposite: keep definitions on each Collection. Rejected — it's the direct cause of the PRD's own "cross-nexus queryable" constraint going unmet (per-collection IDs can't match across Collections) and forces duplicate definitions. This is precisely what PropertiesV2 replaces.
- **Fully-flat, no-assignment (the Obsidian model).** One global registry, every page free to hold any property, a type-hint only, no validation. Rejected — it discards the Notion-side structure Pommora exists to provide (a Collection validating its pages' shape). The hybrid keeps validation while gaining the global-ness.
- **Per-assignment option subset/extend** — rejected for B-1's fully-shared coherence (the opposite was weighed and named).

#### Reconciliation Forecast (what becomes false if this ships)

- `PommoraPRD.md` §Properties ("schemas scoped per Type"), §Storage, §v1-Scope "Out: ad-hoc properties" — restate as definitions-nexus-wide + per-collection assignment.
- `Properties.md` (the per-Type schema framing + "Where Properties Live"), `Collections.md` (§Sidecar+Schema `properties[]`; §Move Semantics "strips properties" → "adopts by assignment"), `Architecture.md` (per-collection schema + the migration section), `Structure.md`. Each is a targeted rewrite, not a note.
- Code: the six per-collection spots (the `schemas.ts` sidecar field, the `SchemaTarget` repoint, the IPC folder-resolution, the preload contract, the renderer ancestor-walk, the type/tree model) + the SQLite `property_definitions` owner-keying. Enumerated in Sources.

#### Don't-Forget Sweep (structural)

- **No migration (V2):** F-1's clean-slate wipe dissolved it — the registry starts empty, no per-collection defs to collapse, no page values to re-key. The only "migration" is a code change: the sidecar schema field flips `properties: PropertyDefinition[]` → `properties: string[]` (assignment ids). No two-phase data pass, and no un-migrated-sidecar backward-read path (there are none post-wipe).
- **Rollback:** the Delete snapshot (C-2) is the recovery path for a destructive scrub.
- **Agent legibility:** `.nexus/properties.json` is a new legible JSON config (peer of `settings.json`) — passes the "no data trapped in a blob" line; values stay in plain frontmatter.
- **Fan-out / concurrency:** a global Clear/Delete is one atomic multi-file transaction (the existing `SchemaTransaction`) across every assigning Collection — all-or-nothing, archived first.
- **Compatibility:** foreign frontmatter + the by-shape value codec unchanged; the SQLite index rebuilds on a version bump.

#### Adjacent Cleanup (surfaced while grounding — ride-along vs own-pass)

The data layer was the first thing rebuilt from Swift; the property-plumbing touches it, so these were scoped.

**Ride along with the property work (mechanical, in code we're already editing):**
- **One generic `.nexus` map-store factory.** `io/{folds,tableHeadingColumns,activeViews,viewOrders}.ts` are byte-identical across module + IPC + preload (only the value-validator differs) — 3-layer triplication × 4. PropertiesV2 *adds* `.nexus` stores (the registry + the assignment/archive plumbing), so build the factory **first** and the new stores are one line each (~140 LOC → ~40, plus the new stores free).
- **Hoist the 14× `refreshSessionIndex(root)`.** Repeated in every `mutate.ts` dispatch branch; hoist to one post-`dispatch` call in `handleMutate`. Pairs with the `setProperty` branch the property work touches.

**Own pass — direction now set by Nathan:**
- **SQLite index rebuilds on EVERY mutation, nothing reads it — investigated: it's a cleanup, not a kill.** `refreshSessionIndex` fires from 14 `mutate.ts` sites (V2 count), each a full `readNexus` walk + DB re-populate, while `sessionDb()` has zero readers. Root cause: a **self-documented stopgap** — the incremental machinery is **already built + tested** (`index/upsert.ts` per-entity `upsert*`; FK cascade-deletes already in `index/schema.ts`) but **unwired**; the cold build is reused for correctness-by-reuse until a consumer lands. **Direction:** *gate now* — stop the per-mutation full rebuilds (a "reload the entire Y on every X" with no reader to justify it; the index self-heals on next open); *wire the pre-built upserts op-by-op when a query consumer lands* (~half-day; keep the coarse rebuild only for rename/move — the link-orphaning ops — per `Architecture.md:117`'s ratified design). Not a kill; a defer-plus-degate.
- **Agenda-write CRUD → STAYS.** Agenda-write is coming soon; agenda is not being scoped here. Keep `crud/agendaEntity.ts` + the agenda schema CRUD; document as staged-not-wired (like the Properties stubs), don't delete.
- **Swift-compat → FINAL departure.** This is the last cut from Swift-compatibility. Remove ALL Swift-compat vestiges — `SWIFT_ONLY_ACCENT`, the `sidebar_sections` legacy migration, `SWIFT_DEFAULTS_VERSION` + the settings backfill, and the **Swift-accent read-mapping**. **V2 correction — KEEP `colorMap.ts`:** the review found it ALSO normalizes Notion + generic color names onto the chip palette (load-bearing), not a pure Swift artifact — strip only its Swift-accent branch, not the file. React owns its palette outright now. Its own cleanup pass.

**Skip:** the `relPosix` dedup (now a single caller — the handoff was stale) + the `str`/`asString` merge (low value, non-identical semantics).

#### Lessons

- The pipeline being **schema-as-a-parameter** + values being **ID-keyed** is what makes a paradigm flatten a seam-repoint instead of a rewrite — a payoff of the original ID-first design. → routes to the Studio rules on why ID-keyed/source-agnostic seams are worth the upfront cost.
