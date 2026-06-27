### Pommora — Context (Current Build-State)

 - **Read after `Handoff.md`.** Handoff is the *journey + what's next*; this is *where the project actually stands right now* — a status map of every subsystem across both builds. It points to the durable docs; it never restates them.

 - **Not the spec, the roadmap, or the log.** Product intent → `PommoraPRD.md`; on-disk + architecture spec → `Features/Architecture.md`; roadmap → `Framework.md`; locked decisions + ship log → `History.md`; branch quirks + hard rules → `CLAUDE.md`. If a fact lives in one of those, this doc links to it instead of copying it.

 - **It drifts by design — so maintain it.** A current-state doc rots the instant code changes — exactly the failure the "documentation altitude" rule warns about. It earns its keep only if it's updated every session (alongside Handoff), held to *status + pointers* (never restated specs or file dumps), and re-grounded against code before its cells are trusted after major work. The statuses below are code-grounded as of the last pass.

**Status legend:** **Built** (works, wired into the running app) · **Partial** (real + wired, with a named gap) · **Stub** (scaffold exists, no behavior / no call sites) · **Parked** (specced, deliberately unbuilt) · **—** (not started).

#### The Two Builds

Same product, built twice, in one repo on one `main`. **React catches up to Swift; it never leads** — net-new subsystems Swift hasn't shipped stay out of scope until Swift has them.

- **Swift** (native SwiftUI, repo root `.claude/`) — the reference build, and ahead on the *view + inspector + properties* surfaces (Table **and** Gallery renderers, a working properties inspector, read-only Agenda surfacing). Work happens on `main`.

- **React** (Electron rebuild, `React/`, authoritative docs `React/.claude/`) — has caught up on the data layer, the core editor, the sidebar, and connections, and has *pioneered* a few editor surfaces (full table editing, locked-header views, the Subfield footer). It still trails Swift on views, properties UI, and inspector content. Work happens in the `pommora-react` worktree, merged when done.

#### Foundations — Verified Aligned

The on-disk contract is the portable spine, and both builds speak it identically (code-grounded this pass): the sidecars (`_pagecollection.json` / `_pageset.json` / `_area.json` / `_topic.json` / `_project.json`), the `.md` page envelope (YAML frontmatter + body, foreign keys preserved by value), `tier1/2/3` as bare ULID arrays at the frontmatter root, the `$rel` / `$status` property encoding, and the agenda `.task.json` / `.event.json` shapes. `modified_at` is aligned too — stored stamp wins, file mtime is the fallback, external edits never override it. SQLite is a regeneratable index sitting off the read path in both builds (files are always truth). Swift alone carries a launch-time `SidecarRenameMigration` (legacy `_pagetype.json` → canonical, transactional backup) because only Swift ever has to open a pre-rename Nexus. → `Features/Architecture.md`.

#### Subsystem Status

**Organization Layer**

- **Contexts — Areas / Topics / Projects** — **Built** both builds: three free-standing tiers, folder + sidecar each, sidebar CRUD + reorder. The context *detail view* is a placeholder both sides — the "Contexts are live blocks-pages" vision is unbuilt (`blocks` empty by design); context→context relations Parked. → `Features/Contexts.md`.

**Operational Layer**

- **Pages — Collections → Sets** — **Built** both builds: `.md` pages, infinite-depth Set nesting, schema on the Collection (Sets inherit), full CRUD + rename cascade. Swift's per-Collection "preview-card" open mode is spec-only (ships main-pane only). → `Features/PageCollections.md` + `PageSets.md`.

- **Agenda — Tasks / Events** — data layer **Built** both builds (EventKit-shaped). Surfacing diverges: **Swift Partial** (read-only `CalendarDetailView` via the Calendar pin), **React Parked** (data adopted, nothing rendered — a task/event can't even be selected). EventKit sync deferred both. → `Features/Agenda.md`.

**Singletons**

- **Homepage** — **Stub** both builds: data layer + a placeholder view holding the nexus name and an optional banner; the composed-blocks dashboard (`blocks`) is empty/unbuilt. → `Features/Homepage.md`.

- **Settings** — **Partial** both builds: `.nexus/settings.json` (labels + accent, plus `subfield` in React) is stored, read, and wired (accent applied app-wide, labels on headers); the editing UI is a blank placeholder — you hand-edit the JSON.

**Editor & Properties**

- **MarkdownPM** — **Built** both builds (Swift = TextKit 2 + swift-markdown; React = CodeMirror 6): inline marks, headings with chevron folding (persisted to `folded_headings`), lists + task checkboxes, blockquote, code, `[[ ]]` connections + autocomplete, native menus. → `Features/PageEditor.md` / React `Features/MarkdownPM.md`.

- **Tables** — the live editor-parity gap. **React Built** (full GFM editing: column drag-reorder, dash-count resize, grip menu, nested cell editors). **Swift render-only** (GFM parses + styles, pipes hidden, zero editing UX — matches the Swift spec's "to be implemented").

- **Properties** — *inverted* parity. **Swift Built** (`FrontmatterInspector` mounts `PropertyPanel` with editors for every property type when a Page is selected); the `PropertiesPulldown` variant is built-but-unwired (the planned inspector→dropdown move hasn't happened). **React Parked** (property data round-trips, but zero editing UI — empty inspector, stub icon-picker). → `Features/Properties.md`.

- **Connections / tier relations** — **Built** both builds: body `[[Title]]` renders as styled inline colored text (3-state resolved / phantom / ambiguous) with rename-cascade + autocomplete; `tier1/2/3` edited via a context picker (Swift renders the tier values as `ContextChip`s in the properties surface). → `Features/Connections.md`.

**Chrome & Detail Surface**

- **Sidebar** — **Built** both builds: create / rename / delete / reorder, PommoraDND drag, persisted disclosure. → `Features/Sidebar.md`.

- **Detail banners** — **Built** both builds: container/detail surfaces render a cover banner (frontmatter `cover`, nexus-relative path) with a set/change/remove menu. **Locked-header** (pin banner + title while the body scrolls) is **React-only** — the real Swift port target (the Handoff's "port banners" line is imprecise: banners exist; the pin behavior is what's missing).

- **Inspector pane** — *inverted* parity. **Swift Built** (trailing `.inspector`, shows page properties via `FrontmatterInspector`, ⌥⌘0 toggle). **React Stub** (full-height scaffold that toggles + resizes but renders nothing). An LLM/CLI inspector is a Prospect both sides.

- **Subfield (footer)** — **React Built** (breadcrumb + dimmed forward ghost-crumb + live per-view stats + slide toggle, persisted under `subfield`); the reorder UI is the one pending piece. Swift has the original footer React ported from (its current feature set wasn't re-grounded this pass). → React `Features/Subfield.md`.

**Views**

- **Table / Gallery** — **Swift Built** (both renderers: an NSOutlineView table + a SwiftUI gallery grid, fed by one `ViewPipeline` doing filter / group / sort). **React Partial** (table built; no gallery). The Swift Handoff names "Gallery" as next-up — that's the Views-UIX config layer (layout pane, sort/group UIX), not the renderer, which already ships. → `Features/Views.md`.

**Parked**

- **Canvas** — **Parked** both builds: React carries a complete locked spec (full-SVG; text-blocks / ink / lines / shapes; JSONCanvas-shaped `.canvas` files; `![[canvas:ULID]]` embed) with zero implementation; Swift has neither code nor spec yet.

#### Cross-Build Parity

The actionable deltas — distilled, code-grounded except where flagged.

- **Swift owes React:** table *editing* (Swift is render-only) and **locked-header** detail views (pin-on-scroll).

- **React owes Swift:** the **Gallery** renderer + the broader view system, the page **Properties** UI, **Inspector** content, and **Agenda** surfacing.

- **Both still pending:** Homepage composed-blocks, Settings editing UI, Canvas, and the Contexts blocks-page detail view.

- **Per the Handoffs (not re-grounded this pass):** React's sidebar empty-row-click behavior and an Icon-Picker rework are noted as cross-build polish — verify against code before acting.

- **Fully aligned:** the entire on-disk / data layer, the core editor, the sidebar, and connections.

#### Repo & Branch State

Both builds live in one repo on one `main`. Swift work happens on `main`; React work happens in the `pommora-react` worktree and merges back when done. The earlier multi-worktree refactoring program is collapsed; live worktrees are `main` + `pommora-react`. Session-level detail (uncommitted parallel edits, what's pushed) → `Handoff.md`.
