## Refactoring Roadmap (Swift Build) — Post-Foundation-Hardening

Sequences the remaining debt from `06-20-Codebase-Audit-And-Reorg.md` into dependency-ordered phases. **Altitude:** this is a roadmap — each phase later gets its own TDD plan when we execute it; it is not itself step-by-step. A `// Planning` doc: consume into work, then remove.

**Baseline:** branch landed on `main` (merge `5b82a1b`); ~1,285 tests green. The audit's snapshot was the pre-Foundation tree at 1,272 tests — several items below are already consumed.

**Status (2026-06-21):** Phases **A, B, C, H complete** (1,291 tests green). The C-deferred magic-numbers → `PUI` + `.hoverFill()` and the `Core/Components/Domain/Features` grouping are done (plus a `Features/Toolbar` extraction + `NavDropdown`→`Navigation` rename). **H** was closed by a simplification-review pass — Agenda title-sort DRY (`NameCollisionCandidate.sortedByTitle()`), a shared inline-rename responder-hop (`InlineRenameFocus`), a dropped single-use `View.if`, and a decorate-sort of `ViewSortComparator` — over the validator typed-throws. **Phase F is DROPPED — see its section.** **Remaining: D (next marquee), E, G** (the still-deferred `PropertyValue` datetime → `IndexDateFormat` and the tangled `NexusAdopter` / `PageTypeManager` splits live under G).

---

### Starting Point — What Foundation Hardening Already Consumed

| Audit item | Status |
|---|---|
| §6 🔴 the 5 latent bugs | ✅ Fixed (A1–A5) |
| §2.3 dead code — `IconPickerField`, `MultiSelectChips` add-path | ✅ Removed (B1, B2) |
| §2.3 dead code — `OrderResolver.titleKeyPath`, `NexusAdopter.skipped` | ⛔ Dropped — false positives (both are live) |
| §2.3 dead code — `PropertiesPulldown` VM | ⏳ Remaining (Phase A) |
| §3.1 filename-safety rule, index `upsertContext` ×3 | ✅ Done (C1, C2) |
| §3.1 SavedView panes, Page-CRUD scopes | ⏳ Remaining (Phase E) |
| §4 move 1 — `Chips` → `Components/Chips` | ✅ Done (parallel session) |
| §4 moves 2–5, full `Core/Components/Domain/Features` reorg | ⏳ Remaining (Phases C, D) |
| §5 Codable / god-files / modernization / test-support / PUI | ⏳ Remaining (Phases B, C, D, F, G, H) |
| §6 🟠 on-disk ratifications, 🟡 version-stamps / `AreaColor` / `catch {}` | ⏳ Remaining (Phase A) |

---

### Decisions Needed (Ratify at Phase A)

**RATIFIED 2026-06-20** (recorded in `History.md`). Outcomes: #1–4 as recommended; **#5 kept silent** (no change — self-heal favored over read-purity); **#6 → full removal** of the Area color feature (Areas identified by icon only). The "confirm paradigm-solidifying choices" HARD RULE — these on-disk shapes hardened by accident.

1. **Adopted-Page id** = `SHA256(path)[:16]` + `adopted-` prefix. Path-derived + stable (idempotent re-adoption) — intentional, but the digest length/prefix were never ratified. → *Rec: ratify as-is; 64 bits is ample at personal scale.*
2. **Option-value minting** — Status mints `opt_<ULID>`, Select mints a bare `ULID`. → *Rec: unify to `opt_<ULID>` (typed, greppable).*
3. **`context_links.id`** — `UUID` in `IndexBuilder` vs `ULID` in `IndexUpdater`. Regeneratable, low stakes. → *Rec: unify to `ULID` (convention).*
4. **`schemaVersion` "current" constants** scattered as bare literals (2 / 1 / 1). → *Rec: one shared `SchemaVersions` source.*
5. **`loadAll` heal-on-read** mints + rewrites sidecars on the **read** path (silently writes user files on first open). Genuine paradigm question. → *Rec: keep the self-heal but make it explicit/logged, not silent — or gate behind a one-shot migration pass.*
6. **`AreaColor.blue` == `.accent`** — both map to `Color.accentColor`, so saved "blue" vs "accent" are indistinguishable. → *Rec: collapse to one case (migrate stored values) or give `.accent` a distinct color.*

---

### The Sequence — 3 Stages, 8 Phases

Each phase: **Goal · Scope · Depends · Risk · Effort · Payoff.** Effort in Claude-sessions.

#### Stage 1 — Foundation (Settle + Enable)

**Phase A — Decisions + Cleanup Sweep**
- **Goal:** settle the unratified shapes and strip low-value noise before the reorg reorganizes around it.
- **Scope:** ratify the 6 decisions above; strip version numbers from code comments (~20 sites incl. `FrontmatterInspector:100`) keeping the "why"; resolve `AreaColor`; `SidebarConfirmation` → use renameable labels not hardcoded "Vault"/"Collection"/"Set"; replace bare `catch {}` on async paths with logged errors; remove the `PropertiesPulldown` VM if still vestigial; route `NexusManager.renameRoot` through `FilenameSafety` (it still inlines its own char check and **permits `\` the validators reject** — a real consistency gap C1 left behind); dedup the XCTest launch-modal guard (quirk #16) — 3 copies (`NexusStore`/`NexusEnvironment`/`NexusManager`) → one shared helper.
- **Depends:** decisions ratified. **Risk:** Low (subtraction). **Effort:** ~1 session.
- **Payoff:** a clean, ratified base; nothing stale carried into the reorg.

**Phase B — Test-Support Module (`PommoraTestSupport`)**
- **Goal:** extract the shared fixtures so every later TDD-gated phase is cheaper and the §7 coverage gaps start closing.
- **Scope:** new target with `TempNexus.make()`, `makePageType/Collection/Set`, `writePage`, `makeIndex(at:)`, the Agenda literal builders; collapse the 3 parallel Area/Topic/Project manager-test suites; seed the highest-value stress coverage (boundary caps, concurrency on one `dbQueue`, malformed/Unicode titles, and the `PropertyValue` multi-probe decode — §2.3/§7: a value that is both URL-and-date or both `FileRef`-and-multiSelect).
- **Depends:** nothing. **Risk:** Low (test-only). **Effort:** ~2 sessions.
- **Payoff:** −test-loc; cheaper TDD for C–H; the audit's #1 stress gaps begin closing.

#### Stage 2 — Structure (The Structural DRY)

**Phase C — Shared-Primitives Extraction + Folder Reorg + PUI Enforcement**
- **Goal:** give the emergent shared layer a real home (the §4 `Core/Components/Domain/Features` shape) so DRY for views/styling is the path of least resistance.
- **Scope:** `FlowLayout`/`FlowingHStack` → `Components/Layout`; finish formatters → `Core/Formatters` (extend A2's `IndexDateFormat` to `PropertyValue` + `TimeFormat`/`DateFormat`); misplaced singletons (`SavedConfig` out of `Contexts`, `ReservedTypeID` → `Agenda`); absorb the 1-file folders (`CRUD`, `Ordering`, `Filesystem`) into `Core`; establish the top-level grouping (**move, don't rewrite**); route the ~40 magic numbers through `PUI` + add `.hoverFill()`; consolidate the inline `JSONDecoder`/`JSONEncoder` in `AppState`/`NexusIdentity` through `AtomicJSON`; single-source the Crockford ULID alphabet (duplicated verbatim in `ULID` + `ULIDValidator`); pragmatically strip `how`-explaining comments throughout the touched files per the Studio comment rule (keep only the `why`).
- **Depends:** B helpful, not strict. **Risk:** Low–med (moves auto-track via quirk #2; verify build per move; keep Section/SelectionChrome shapes intact, quirks #8/#9). **Effort:** ~2–3 sessions, incremental (each move a green commit).
- **Payoff:** kills cross-folder coupling; the Components layer becomes real; `PUI` stops rotting toward the ad-hoc state React is climbing out of.

**Phase D — The `Row` Primitive**
- **Goal:** the React build's #1 component lesson — one `Components/Row` (slots: icon · label · trailing · drag-handle · drop-indicator + typed selection/rename state) subsumes the 6-way-duplicated inline-rename wiring, `SelectableRow`/`RenameableRow`, and the drag-ghost color patch.
- **Scope:** build `Components/Row`; re-skin the sidebar onto it (**rewrite, not amend**); render the drag ghost AS the real Row (dissolves the `labelColor` special-case). Shrinks the `SidebarView` god-file as a side effect.
- **Depends:** C (Components home) + B (test net). **Risk:** **Med–high** — load-bearing `SidebarView` (quirks #8/#9: Section homogeneity, `SelectionChrome` via `.listRowBackground`, `.selectionDisabled` propagation). TDD; verify tests *bootstrap*, not just compile. **Effort:** ~2–3 sessions.
- **Payoff:** the single biggest UI-duplication kill; the drag-ghost special-case gone.

#### Stage 3 — Depth (The Deeper Debt)

**Phase E — DRY the Non-Divergent Families (TDD-Gated)**
- **Goal:** collapse the mechanical (non-divergent) duplication; **per-type Context + Agenda managers stay separate** (ratified headroom).
- **Scope:** SavedView pane scaffold (`currentView()` / empty-state / error-banner / the scope→typeID switch ×6 → one scaffold + computed props on `ViewSettingsScope`); Page-CRUD scope path (Collection/Set/Type-root triplication → one scope-parameterized path); `schemaOptionValues` hoist; one asset-import service (`CoverAssetStore`/`AttachmentManager`/banner-inline → one importer, aligned to the React fresh-token naming). *(The Navigation `PinnedManager`/`RecentsManager` `StateJSONStore`-shaped skeleton is **deferred as optional** per §3.1's headroom hedge — not collapsed unless wanted.)*
- **Depends:** B. **Risk:** Med (load-bearing UI/CRUD — TDD-first, one at a time, not big-bang). **Effort:** ~2–3 sessions.
- **Payoff:** removes mechanical duplication without blocking per-type divergence.

**Phase F — Manual `Codable` → Synthesized** — **DROPPED (2026-06-21).**
A survey of all 21 hand-rolled `Codable` types invalidated the premise: Swift's *synthesized* `Decodable` **throws** on a missing in-CodingKeys non-Optional key — it does **not** fall back to the property's default. The pervasive `decodeIfPresent(…) ?? default` here is defensive schema-evolution robustness (a corrupt sidecar loads with defaults instead of failing), which synthesis can't replicate without regressing decode or changing the on-disk shape. Genuinely deletable subset: ≤2 trivial types (`PageDisplay`, maybe `SettingsLabels`) — nowhere near "−1,000 loc". The hand-rolling is justified; left as-is. (A minor *DRY* pass remains possible — Area/Topic/Project `Codable` is byte-identical modulo `tier`, Agenda Task/Event parallel — but that keeps the defaulting and is not this phase.)
- **Goal (original):** −~1,000 loc of lockstep-fragile hand-rolled `Codable`.
- **Scope:** `PageType`/`Collection`/`Set`/`SavedView`/`PropertyDefinition`/`Area`/`Topic`/`Project`/`Agenda`/`AppState` → synthesized + `decodeIfPresent` defaults; custom **only** for genuine legacy keys (`vault_id`, `visible_properties`, `relation_scope`, favorites→pinned). TDD the legacy-key + foreign-frontmatter-preservation paths first.
- **Depends:** B. **Risk:** Med (must preserve legacy + foreign-frontmatter round-trips — TDD-gated). **Effort:** ~2 sessions.
- **Payoff:** −~1,000 loc; the encode/decode lockstep-fragility class gone.

**Phase G — God-File Breakups**
- **Goal:** split the remaining multi-concern files for cohesion, testability, and fewer merge crashes.
- **Scope:** `NexusAdopter` (model / classifier / disk-mutation); `ViewSurface` (extract rename / delete / cover; simplify the `columns` copy-mutate force-show, §2.3); `PageTypeManager` (split Collection + Schema CRUD); `IndexQuery` (`FilterBuilder` → own file); `GroupingPane` (extract reusable rows → `Components`, label catalogs). (`SidebarView`'s row-duplication handled in D.)
- **Depends:** C (Components home for `GroupingPane`'s rows) + B. **Risk:** Med (quirks #8/#9 for view files). **Effort:** ~2–3 sessions.
- **Payoff:** cohesion + testability; fewer `recursivelyDiffRows` crash surfaces.

**Phase H — Concurrency + Typed-Throws Modernization**
- **Goal:** bring the remaining idioms current — constraints-respecting (no SwiftData; the AppKit bridges stay intentional).
- **Scope:** `DispatchQueue.main.async` → `Task { @MainActor }` (**7 sites**, re-grounded — but `NexusFileWatcher` + `NSTableSelectionStyleSuppressor` are AppKit-bridge-adjacent, so **per-site check**: the off-main hop may be intentional, no blanket sweep); typed `throws(ValidationError)` on the **9 entity validators** (the other 4 `*Validator` files are separate); Swift `Regex` for `ConnectionScanner` (`try! NSRegularExpression`); hand-rolled comparators → `sorted(using:)`; `if(condition:)` View ext → always-apply + gated. *(No Swift Testing migration — the unit suite is already 100% Swift Testing; the only remaining XCTest is the auto-generated XCUITest scaffold, which has no Swift Testing equivalent. Leave it, or delete the boilerplate.)*
- **Depends:** none strict; **after** the structural churn so it doesn't rebase across moves. **Risk:** Low (mechanical). **Effort:** ~2 sessions.
- **Payoff:** idiom; the formatter-drift bug class fully closed (formatters consolidated in C).

**Rough total: ~14–18 sessions across 8 phases — a program, not a sitting.**

---

### Sequencing Rationale

- **A first** — decisions unblock everything; settling paradigm + removing noise before the reorg means the moves don't carry stale shapes.
- **B early** — the audit ranks test-support last *in isolation*, but as a prerequisite it pays compounding interest: every TDD-gated phase (D–G) is cheaper with shared fixtures already extracted.
- **C before D** — the `Row` needs a `Components` home; the reorg is low-risk "move don't rewrite" and creates the layer D and G land in.
- **D as the marquee** — highest-value single component, but a rewrite touching load-bearing `SidebarView`, so it waits for the test net (B) + the home (C).
- **E/F/G/H last** — the deeper, more independent debt, sequenced med→low risk *after* the structure is stable so they don't churn across folder moves.

---

### Cross-Cutting Cautions

- **Quirks #8/#9 bind D + G's view files** — verify tests *bootstrap* (non-zero executed count), never trust compile-only green.
- **Parallel-session staging** — stage explicit files per task, never a directory or `-A` (the entanglement lesson). The comment sweep (A) and the reorg (C) touch many files → highest entanglement risk; serialize with the React/parallel session or stage tightly.
- **Re-ground at plan time** — each phase's `file:line` targets are the audit snapshot; this doc re-grounded structure / god-file sizes / version-stamps, but not every §3.1 line. Confirm before each phase's TDD plan.
- **React lessons (§9)** carried in: `Row` (D), fresh-token asset naming (E), components-first + rewrite-don't-amend discipline (C/D), PUI-enforcement-not-authoring (C).

---

### Phase A — Execution Status

**Done (green commits on `refactoring`):**
- Decisions ratified + recorded (`History.md`).
- Area color removed — `8e41064` (1283 tests).
- `renameRoot`→`FilenameSafety` + XCTest-guard dedup (`ProcessInfo.isRunningXCTests`) — `7197307`.

**Finding — `PropertiesPulldown` "dead VM" is a FALSE POSITIVE.** `PropertiesPulldownViewModel` is referenced only by its own test suite, never instantiated in production (the View re-implements the logic as private `@State`). It's a *tested parallel implementation*, not unreferenced dead code — removing it deletes real coverage. Proper fix = rewire the View to *use* the VM (removes the duplication the other direction); bigger than a Phase A subtraction. **Deferred** to whenever the View is next touched (Phase D/E).

**Executed (green commits on `refactoring`, 1283 tests):**
- `opt_` on Select option minting — `e0119fc` (verified nothing parses the prefix → safe).
- `context_links.id`→ULID + `ULID.generate`/helpers/`alphabet` made `nonisolated` — `98a7b87`. The UUID/ULID split was *forced* by isolation, not sloppiness: `IndexBuilder` is `nonisolated` (off-main cold rebuild) and `ULID.generate` was `@MainActor`-inferred under default isolation. Making the pure generator nonisolated is the correct fix and unifies the index on ULID.
- `SchemaVersion` registry — 8 nexus-entity sidecars centralized (`a056d0b`); app-level state (AppState/NexusState/NexusIdentity) kept separate.
- Forward-looking version-stamp promises removed — `cbc1b7e` (`StatusGroupsEditor`, `FrontmatterInspector`; the `PommoraApp` "v0.6.0" stamp didn't exist on this branch).

**Two more audit items were FALSE POSITIVE / BLOCKED — verified against code, not actioned:**
- **`catch {}` "silent error swallowing"** — FALSE POSITIVE. The called managers self-surface via `pendingError` + rethrow (verified `movePage`:750, `deletePageCollection`:500); the view's empty catch absorbs the *rethrow* after the toast already fired. Cleanup-after-success catches are intentional.
- **SidebarConfirmation hardcoded labels** — BLOCKED. Wiring needs a clear authoritative label source, but the architecture is tangled: context-tier labels live in `TierConfig.tiers` while `SettingsLabels` carries `project` + the Pages-side entities (no `area`/`topic` singular). Resolving that duplication is the prerequisite — not a Phase A swap.

**Phase A complete** — every actionable item executed + verified; the three non-actionable ones (PropertiesPulldown, `catch{}`, SidebarConfirmation) are grounded findings, not skipped work.

---

### Review Status

Adversarially reviewed against the live code + git history — verdict **minor issues, all folded**. Verified: every "done" claim true against its commit, both dropped audit items genuinely live, constraints (separate managers / no SwiftData / intentional AppKit bridges) respected, sequencing sound. Folded corrections: §2.2 utility hoists + `renameRoot` consistency gap (A/C), DispatchQueue re-grounded to 7 sites with AppKit-adjacent carve-outs (H), unit suite already 100% Swift Testing so no migration exists (H), `ViewSurface.columns` + `PropertyValue`-probe simplifications homed (G/B), Navigation store-collapse logged as deferred-optional (E).
