## Data Layer — Build Log

A per-phase record of what was built, why, how it departs from the Swift implementation and why, and **⚐ review flags** — uncertainties left deliberately for a later code-review + simplification pass (each flag is a *where* + a *why*). Forward spec lives in `Data-Layer-Design.md`; this is the retrospective. Appended as each phase ships.

Convention: everything is headless (tests-only, no UI wired); every commit is green (typecheck + build + vitest).

### Phase 0 — contracts, ID owner, value codec, atomic I/O · `d523dcc`

**What.** `shared/result.ts` (`Result`/`PommoraError` + `ok`/`err`/`fail`); `shared/propertyValue.ts` (the `PropertyValue` union + `parse`/`encode`); `main/ids.ts` (`newId` via ulidx monotonic, `isUlid`, `adoptedId`); `main/io/atomicWrite.ts` (`atomicWriteFile`, `writeJson`, `mutateJson`, `stableStringify`, later `trashWithTimestamp`).

**Why.** Everything downstream needs a never-throw result type, a safe-write primitive, identity, and the value codec. Built first, in isolation, because they're pure and the codec is the single highest-risk module.

**Swift delta + why.** The `PropertyValue` codec is a ~60-line pure function pair instead of Swift's ~117-line custom `Codable` with shape-sniffing `init(from:)`/`encode(to:)` — same precedence, no `Codable` ceremony, no `any Decoder`. `adoptedId` is now one owner; Swift (and our own early read engine) had the sha256 logic duplicated. Atomic write is the *default* path, not a special helper.

**⚐ Review flags.**
- `propertyValue.ts` date check is **format-only** (`/^\d{4}-\d{2}-\d{2}$/`): `"2026-13-45"` classifies as `date`, where Swift's `DateFormatter` rejects it → `select`. Round-trip is byte-stable either way (both re-emit the string), so impact is the in-memory `.kind` only. *Decide whether real date validation is worth it; schema is the type authority anyway.*
- `propertyValue.ts` URL test is a scheme regex, not Swift's permissive `URL(string:)`. Close, but edge strings (`"Note:x"` → url) may differ. Same byte-stability caveat.
- `parsePropertyValue` **throws** on an unrecognised shape (matches Swift) — but the design ethos elsewhere is "lenient by default." *Confirm throw vs. returning `{kind:'null'}`.*
- `result.ts` ships `ok`, `err`, **and** `fail`. CRUD uses `ok`/`fail`; `err` may be unused → **simplification candidate** (drop `err` or justify it).
- `mutateJson` is read-modify-write but **not transactional**: two concurrent `mutateJson` calls on the *same* file can interleave (read A, read B, write A, write B → A lost). Safe only if same-file writes are serialized. *Flag for a per-file write queue if concurrent same-file mutation becomes real.*
- `FileRef` uses snake_case keys (on-disk DTO) — unusual in TS. Intentional (round-trips as-is); confirm acceptable.

### Phase 1 — page file engine · `c0ba4df`

**What.** `main/io/pageFile.ts`: `splitEnvelope`/`assembleEnvelope` (the `---\nfm---\n\nbody` contract) + `mergeFrontmatter` (parse original frontmatter to a yaml Document, `set`/`delete` only modeled keys, reassemble) + `writePageFile`.

**Why.** The write counterpart to the existing `readPage`. The foreign-preservation guarantee is the load-bearing correctness property of the whole layer.

**Swift delta + why.** Swift's lossy typed `Codable` round-trip forced a hand-rolled ~70-line Yams `Node` merge to retain foreign keys, and it still dropped comments. The yaml Document API retains foreign keys **and comments** natively because we never reconstruct the object — we touch only modeled keys on the parsed original. Net: less code, strictly more preserved.

**⚐ Review flags.**
- **First-write styling may not be byte-identical to Swift/Yams** (flow vs block, quoting) on a freshly-set modeled key. Accepted by design (value + envelope-frame equality, not serializer quoting; re-save is idempotent). *Reviewer: confirm the reflow tolerance is acceptable, and that no consumer depends on exact Swift bytes.*
- `mergeFrontmatter`'s contract — *set if in `modeled`, else delete (for keys in `modeledKeys`)* — is a **footgun**: a caller that lists a key in `modeledKeys` but omits its value silently deletes it. Works because callers pass a deliberate governed set (full set for create, `['modified_at']` for body update). *Consider a safer API (explicit `{set, clear}`) or a guard.*
- Corrupt non-map frontmatter is **silently discarded** (`doc = parseDocument('')`). Acceptable (it can't be page frontmatter), but it's silent data loss. *Confirm.*
- `splitEnvelope` strips exactly one separator blank line; extra leading blank lines stay in the body. *Confirm this matches Swift's body semantics.*

### Phase 2 — sidecar schemas, kind authority, sidecar I/O · `8f71db9`

**What.** `shared/schemas.ts` (zod v4: `baseSidecar`/`contextBase` builders → pageType/collection/set/area/topic/project + `pageFrontmatter` + `PAGE_MODELED_KEYS`); `main/kind.ts` (`resolveKind`); `main/sidecarIO.ts` (`readSidecar`/`writeSidecar`).

**Why.** The codec/type/validation layer CRUD writes through, and the path-based kind authority CRUD and the reader rely on.

**Swift delta + why.** One zod schema is simultaneously validator, on-disk format, and static type (`z.infer`) — replacing Swift's separate struct + custom `Codable` + `CodingKeys` (which drift; that drift caused the tier-shape doc bug). `z.looseObject` retains foreign keys on **all** JSON sidecars, closing Swift's silent-drop data-loss gap. Shared builders collapse Swift's three byte-identical context managers. Kind authority is a stateless fs probe, not an `@Observable` singleton in an injection graph that could SIGTRAP.

**⚐ Review flags.**
- **Schema coverage is partial:** folder + context sidecars + page frontmatter only. The `.nexus/*` **singletons** (settings/state/nexus/saved-config/sidebar-sections/tier-config/homepage) are **not modeled yet**, and `readNexus` still reads them with its own untyped `readJson`. *This is the readNexus-DRY-refactor debt — two ways to read sidecars coexist until singletons land.*
- Area `color` is `z.string().optional()`, **not** the 10-case `AreaColor` enum — lenient (an unknown color survives rather than failing the whole sidecar). *Decide: validate against the enum (with `.catch`) or keep lenient + coerce at read.*
- `property_definitions` is an unmodeled `z.array(z.looseObject({}))` placeholder until Phase 4.
- `resolveKind` returns the **first** matching sidecar; a folder carrying two sidecars (shouldn't happen) is silently disambiguated by iteration order, and it does up to 8 `stat`s per folder. *Reviewer: detect-ambiguity? read the dir once instead?*
- `readSidecar` returns `null` on validation failure (e.g. missing `id`) — discarding any foreign data on a malformed sidecar. Swift was more lenient. *Confirm null-on-invalid isn't too lossy.*

### Phase 3 — CRUD lifecycle · `18cda71` folder · `d55dc5a` page · reorder (this commit)

**What.** `crud/folderEntity.ts` (one `create`/`rename`/`delete`/`updateSidecar` for all six folder entities) + `crud/page.ts` (`create`/`rename`/`delete`/`updatePageBody`/`move`) + `crud/reorder.ts` (`setStateOrder` → state.json for vaults/tiers; `setContainerOrder` → sidecar for collections/sets/pages). `trashWithTimestamp` added to `atomicWrite.ts`. The operation set is now complete: create/rename/delete/update/move/reorder.

**Why.** The actual mutation capability — the spine of the app. The folder factory is the big DRY win (Swift copy-pasted these ladders across managers).

**Swift delta + why.** One generic factory replaces per-entity managers + their copy-pasted rollback ladders. No `@MainActor`/`Sendable`/DI — plain async functions. No security-scoped bookmarks. Delete = in-nexus `.trash` (recoverable, files canonical) rather than OS trash. Errors flow as `Result`, never thrown.

**⚐ Review flags.**
- `createFolderEntity` writes `{id, ...extra}` **without schema-validating** the result — it trusts the caller's `extra`. A wrong field shape writes a malformed sidecar (caught only on next read). *Validate-on-write against the kind's schema?* (Needs a kind→schema map — couples the factory to schemas; weigh against DRY.)
- **No `validators.ts` yet.** Name-collision is inline; the design's richer validators (page title shape, tier-target existence, property-type match) are unbuilt. *Phase 3/4 debt.*
- `updateFolderSidecar` merges `patch` over current but **doesn't re-validate** the merged object.
- `movePage` does **not** strip cross-type properties (a page moved to a type with a different schema keeps stale property keys). Deferred to Phase 4 (needs the schema-aware property layer). *Known gap.*
- Name safety is minimal: rejects `/`, `\`, `.`/`..`, blank. It does **not** strip a trailing `.md` (title `"Note.md"` → file `Note.md.md`), nor guard OS-illegal chars (`:`), trailing spaces, or reserved names. *Reviewer: harden name validation centrally (a shared `validateName`).*
- `crud/folderEntity.ts` and `crud/page.ts` each re-implement `exists`, `invalidName`, `nowIso`. **Small DRY duplication** — candidate to hoist into a shared crud util.
- `reorder.ts` persists whatever id list it's given — it does **not** validate the ids exist. Harmless on read (`resolveOrder` ignores unknown ids), but a garbage/stale id silently lands in the order array. *Confirm no existence check is needed, or add one.*
