## Context Block Hosts — Decision Log

> **DEFERRED (parked spec, not active).** Nathan's call: defer *which* surfaces become block hosts — the "future contexts decision" — and finish the locking on the existing homepage host first. This log's storage + seam grounding stays valid and is the head-start for when contexts-as-hosts is picked up; only the product-model fork (A-1: freeform canvas vs auto-seeded) is left open. Do NOT implement from this yet.

Grounded, pre-ratification. Turns "make Contexts first-class block-surface hosts + a standardized per-container SettingsPane scaffold with a footing lock" into a planner-ready spec.

### Frame

- **Purpose:** Give every container surface — the homepage and each Context tier (Area / Topic / Project) — a real BlockSurface, and a standardized SettingsPane scaffold (Icon+Title identity header + a footing lock). Extend the same footing lock to Collections/Sets.
- **Core Value:** A Context is no longer a dead "blank page under a banner" — it's a freeform block canvas like the homepage, and every container has one consistent settings pane whose footing lock freezes that surface.
- **Success Criteria:** Selecting any Area/Topic/Project renders an editable BlockSurface persisted to that context's own sidecar; its SettingsPane shows icon+title + a working footing lock (board freeze); the homepage gets the same pane; Collections/Sets gain the footing lock (their view-lock). No regression to the existing homepage host, the link graph, or rename.

### Sources

- `src/shared/blocks.ts` — `BlockHostRef = { kind: 'homepage' }` (:57) + `coerceBlockHost` (:59, homepage-only); `BlockDoc`/`BlockDocPatch` contract (layout/blocks/locked); entry unions. The seam to widen.
- `src/main/blocks.ts` — `BLOCK_HOSTS` **static one-element list** (:21); `blockHostConfig` **ignores its host param**, hardcoded to homepage.json (:28); `blockFilePath`/`blockHostDir` (:33); locked read-merge-write `mutateDoc` (:38) preserving foreign keys incl. banner; `markdownBlockFiles`/`listBlockBodies`/`rewriteBlockConnections` all iterate `BLOCK_HOSTS`.
- `src/main/paths.ts` — `nexusConfig` → `.nexus/<file>`; `NEXUS_CONFIG_FILES.homepage='homepage.json'` (:52); `blockHostDir` typed to `{kind:'homepage'}` → `.nexus/homepage/` (:44, `HOMEPAGE_HOST_DIRNAME`); `SIDECAR_FILENAME` per kind — `_area.json`/`_topic.json`/`_project.json` (:18).
- `src/main/readNexus.ts` — `readTier` (:321): each context is a **folder** under `.nexus/<tier>/<name>/` with its sidecar inside; node carries `id` (sidecar `id`, else adopted), `title`=folder name, `path`=`.nexus/<tier>/<name>`, `banner`, `icon` (area also `color`). Contexts are **sidecar-mode only** (:425) — a raw-folder nexus (`~/test`) has none.
- `src/main/mutate.ts` — `createContext` (:172), `TIER_DIR` (:49); rename **renames the folder, id stays stable** — *"contexts are referenced by stable id"* (:211-212). The convention that decides the host-ref identity.
- `src/main/sidecarIO.ts` — existing `readSidecar`/`writeSidecar` by (folder, kind) → the seam a context block-doc read/write reuses.
- `src/renderer/src/Detail/ContextView.tsx` — today just `<DetailScaffold owner={findContext(tree,id)} />` (blank). `HomepageView.tsx` is the mirror (renders BlockSurface with `{kind:'homepage'}`).
- `src/renderer/src/Detail/DetailPane.tsx` — routes selection.kind → view (:19); Subfield omitted for homepage+context (:71-75).
- `src/renderer/src/Components/Detail/SettingsPane.tsx` + `SettingsDropdown.tsx` — SettingsPane handles collection/set (+ view-embed scope); `SettingsDropdown` shows it only for `scope==='view'`, else an empty placeholder (:27) — *"other surfaces get a placeholder until their own panes land."* The scaffold target.
- `src/renderer/src/Blocks/BlockSurface.tsx` — the host-facing surface; takes a `BlockHostRef`, threads it into every `window.nexus.blocks.*` call + `useBlockDoc`.
- [[7-10 - Block Surfaces — Decision Log]] — the block-host seam: D-2 (which entity's sidecar holds the doc), G-2 (host surface), G-3 (`blocks_locked` host lock), G-12 (homepage as the dev host, "real hosts land" later).

### Decisions

#### A — Product Model
- **A-1:** [assumed] A context surface is a **freeform block canvas** — identical model to the homepage: empty until the user places markdown/page/view tiles. It is NOT an auto-populated "everything tagged to this context" view. (A user builds that themselves by dropping a view-embed filtered to the context.) ← needs Nathan's yes; it frames the whole feature.
- **A-2:** [confirmed] The banner stays. A context renders its banner (as today) with the BlockSurface below it — exactly the homepage's banner+blocks coexistence (`homepage.json` holds both; read-merge-write preserves the banner).

#### B — Host-Ref Identity
- **B-1:** [assumed] The context `BlockHostRef` carries the context's **stable id** — `{ kind:'context', id }` — matching the codebase's own rule (`mutate.ts:211`, "referenced by stable id"), the existing `SelectionState` context shape (`types.ts:304-312`, id-only), and surviving rename. NOT the path (path-carrying is `Considered & Rejected`). Main resolves id→folder. ← recommend; confirm (technical).
- **B-2:** [confirmed] The id→folder resolver — flagged by review as "the single biggest new machinery" — is **the same context enumeration the dynamic `BLOCK_HOSTS` already needs** (E-1): one "list every context as {id, tier, folder}" walk, reused for both the link-graph host list AND per-op id→folder lookup. Not extra machinery; one helper. `coerceBlockHost` MUST validate the id as a safe path segment (`isUlid`, mirroring the tile-id gate at `index.ts:1053`) — the id builds filesystem paths, so an unchecked value is a traversal hole.

#### C — Storage
- **C-1:** [confirmed] The context block doc (`blocks`/`layout`/`blocks_locked`) lives in the context's **own sidecar** (`_area.json`/`_topic.json`/`_project.json`) — one file, one entity, mirroring homepage.json. Decisive reason: `setBanner`'s context branch (`mutate.ts:311-321`) already writes the context banner to that sidecar under `serializeOnFile(cfgPath)` — so if `blockHostConfig` returns that SAME path, the banner writer and the block-doc writer share one lock automatically (the exact invariant the homepage design exists to hold, `blocks.ts:1-6`). A separate file would forfeit that coordination. `blockHostConfig` branches on host kind; the write stays the locked read-merge-write (banner + foreign keys survive).
- **C-2:** [assumed] A context's markdown-block `.md` files live in a subfolder of the context's folder (e.g. `.nexus/<tier>/<name>/<blocks-subdir>/<ulid>.md`), the way homepage blocks live in `.nexus/homepage/`. `blockHostDir` branches on host kind. ← subdir name is a detail to settle.
- **C-3:** [confirmed] All three tiers share one storage model (folder + sidecar), so one host-kind handles Area/Topic/Project uniformly — no per-tier divergence.

#### D — Tiers & Scope
- **D-1:** [assumed] All three context tiers (Area, Topic, Project) get block surfaces — "contexts" means every tier. ← confirm.
- **D-2:** [confirmed] Collections/Sets gain the SAME footing lock (Tier C container view-lock) in their existing SettingsPane; homepage + contexts get the new stripped scaffold (icon+title + footing lock, no view-config leaves). Nathan-confirmed.

#### E — Adjacencies (blast radius) — concrete seams from the end-to-end trace
- **E-1:** [confirmed] `BLOCK_HOSTS` (`blocks.ts:21`, static) goes **dynamic**: `markdownBlockFiles` (:216) + `listBlockBodies` + `rewriteBlockConnections` + the cold index build (`index/build.ts:296`) enumerate every context host. Cost: one sidecar `readJsonObject` per context per cold build + per page-rename — bounded (few contexts), overlaps `collectNexusData`'s existing context read; never a per-block re-walk.
- **E-2:** [confirmed] IPC: `coerceBlockHost` (`shared/blocks.ts:59`) accepts + isUlid-validates the context ref; `blockHostAnd`'s hardcoded `{kind:'homepage'}` return type (`index.ts:1048`) widens to `BlockHostRef`; all 10 host-taking `blocks:*` handlers (get/save/createMarkdown/removeTile/readMarkdown/writeMarkdown/convertToPage/convertToView/duplicateTile) then flow contexts through. Preload types widen automatically.
- **E-3:** [confirmed] Renderer bugs to fix while wiring: `useBlockDoc`'s reload effect keys on `[host.kind]` only (`useBlockDoc.ts:57`) — must include the host **id** or switching between two contexts won't reload the doc; `ContextView` must memoize the host ref per-id (mirror `HomepageView`'s module-const, but id-keyed); confirm `MarkdownBlock`'s `[tileId]`-only load effect is safe (ULIDs are globally unique, so likely fine).
- **E-4:** [confirmed] Watcher: `watcher.ts:47` ignores `.nexus/homepage` so block-body writes don't force a tree re-walk — each context's block-`.md` subfolder must join that ignore predicate, or every keystroke in a context surface re-walks. The context sidecar FILE stays watched (the tree reads its banner).
- **E-5:** [confirmed] `SettingsDropdown` scope resolution (`viewSettingsScope`) routes homepage + context selections to the new scaffold pane instead of the empty placeholder (`SettingsDropdown.tsx:27`).
- **E-6:** [confirmed] Tests encoding the single-host assumption need updating: `shared/blocks.test.ts:92-96` (asserts `{kind:'area'}`→null), `main/blocks.test.ts` (HOST=homepage, hardcoded `.nexus/homepage.json`), `index/build.test.ts:141`, `mutate.test.ts`, `watcher.test.ts`.
- **E-7:** [open] Testing target: contexts are sidecar-mode-only, so `~/test` (raw-folder) can't exercise them — the gate needs a sidecar-mode fixture (or Nathan's real nexus via CDP). ← resolve in planning.
- **E-8:** [open] Subfield stays omitted for contexts (`DetailPane.tsx:71-75`)? Likely yes (nothing to show), re-confirm once the surface exists.
- **E-9:** [confirmed] `healSplitDoc`/`_blocks.json` legacy fold (`blocks.ts:50`) is a homepage-only migration — a no-op for contexts (they never had the split); don't extend it.

### Core (must-have)
- Context `BlockHostRef` variant + `coerceBlockHost` + `blockHostConfig`/`blockHostDir` branching.
- Context block doc read/write in the context sidecar (reuse the locked read-merge-write; banner survives).
- `ContextView` renders BlockSurface (banner above) with the context host ref (mirror HomepageView).
- IPC bridge accepts the context ref across all `blocks:*` handlers.
- `BLOCK_HOSTS` dynamic enumeration (link graph + rename heal cover context blocks).
- SettingsPane scaffold (icon+title + footing lock) for homepage + contexts; footing lock added to collection/set.

#### Prospects (allowed later, not now)
- Context surface auto-seeding (a fresh context suggests/pre-places a view-embed of its tagged content) — don't foreclose: the block model already allows it as a manual drop.
- Per-tier surface differences (a Project canvas ≠ an Area canvas) — one uniform model now; leave the host-kind open to carry a tier discriminant (it already does).

#### Out of Scope (won't do)
- Changing the Context product meaning (still the org layer; blocks are a surface ON it, not content IN it).
- Reworking the homepage host (only widened, never restructured).

#### Considered & Rejected
- **Path-carrying host ref** (`{kind:'context', path}`) — direct sidecar resolution, no id→folder walk, but goes stale on rename and fights the "referenced by stable id" convention. Rejected for the id-carrying ref (B-1).

#### Lessons
- (pending)
