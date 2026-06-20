# Banner — Design

A full-width cover image at the top of a view, rendered behind the floating glass chrome and shared by every view type. Recreates the Swift build's `ContainerBannerView` mechanism in React + Electron.

## Overview

A **banner** is a full-bleed image at the top of a view's content that sits *behind* the glass sidebar, the window controls, and future toolbar items. One shared mechanism serves all view types. What differs per type is only **which entity owns the banner** and **what a view composes around it** — never the banner itself.

## Architecture

- **One shared `Banner` component + one generic `setBanner` mutation** handle every owner kind. There is no per-type banner code.
- A view that wants extra chrome — the future **Homepage**, with its dynamic widgets/content — composes that **at the view level, around the banner**. The banner manager never knows about it; the banner is always just an image banner.
- **v1 owners:** Vault (`_pagetype.json`) and Context (`_area.json` / `_topic.json` / `_project.json`). Page, Collection, and Homepage are drop-in additions once those content surfaces exist — each supplies an owner kind plus a storage location and reuses everything else.

## On-disk model

- The owner's sidecar carries an optional **`banner`** field: a nexus-relative POSIX path, or absent when there's no banner.
- The image is copied to **`.nexus/assets/<entity-id>/banner.<ext>`** — a per-entity assets folder mirroring Swift. `<ext>` preserves the source format (no re-encode). One banner per entity; replacing deletes the previous file only after the new field write succeeds.
- Sidecars are loose objects, so the field survives a rewrite untouched even where a view doesn't yet read it. The page-level `cover` frontmatter field is a separate concept and is not reused for banners.

## Asset loading — `nexus-asset://`

- Main registers a privileged custom scheme **`nexus-asset`** (standard, secure, stream) that serves files **read-only** from the current session's `.nexus/assets/`.
- URL form: `nexus-asset://nexus/<nexus-relative-path>`, resolved against the session root.
- **Security:** resolve the requested path and reject anything that escapes `<sessionRoot>/.nexus/assets/` (path-traversal guard); serve on GET only. Consistent with the Node-surface hardening posture.
- The renderer's Content-Security-Policy allows images from `nexus-asset:`.
- `readNexus` exposes each owner's `banner` path (a cheap string) on its tree node; the renderer composes the URL. **No image bytes pass through the reloaded state tree** — the cost that base64 would have added on every watcher refresh is avoided, and the browser caches decoded images.

## Layering & mount

- `.detail` is restructured: the scroll container becomes full-bleed (its horizontal/top padding moves to an inner body wrapper that keeps the current sidebar/toolbar clearance). The banner is the scroller's first child.
- Because `.content-pane` paints behind the sidebar glass (z-1) and titlebar (z-2), a full-bleed banner shows through the sidebar frost and under the toolbar with no z-index work — the existing stacking does it.
- The banner is **180px tall, full width, `object-fit: cover`** (Swift's fixed `bannerHeight`, aspect-fill — a fixed height, not a locked aspect ratio). It **scrolls with content** (normal flow, not pinned), matching Swift.
- A shared **`DetailScaffold`** (banner slot + body) wraps the banner-bearing views so the layering lives in exactly one place; a view that passes no owner renders no banner and keeps today's layout.

## Component & UX (`Banner`)

- **No banner:** a slim top strip; on hover, a tertiary-color `plus` + "Add Banner" button fades in (Swift's `opacity(isHovering ? 1 : 0)`). Click opens the native image file picker.
- **Has banner:** the image, the entity name overlaid bottom-leading (Swift parity), and a **native macOS context menu** on right-click offering **Change Banner** / **Remove Banner**. The menu is built in the main process (`Menu.popup`), mirroring Swift's `.contextMenu` and the existing native photo menu.
- A **divider** (separator token) sits below the banner/header, separating it from the content.

## Data flow

- **`pickImage()` IPC** — opens the native image file dialog, returns a data URL or null. Reused by Add and Change (generalized from the existing photo dialog).
- **`bannerMenu()` IPC** — pops the native Change/Remove menu in main, returns `'change' | 'remove' | null`.
- **`setBanner` mutate op** `{ path, kind, dataUrl }` (removal carries no image): decode bytes → write `.nexus/assets/<id>/banner.<ext>` → set the sidecar `banner` field → delete the previous file only after the write succeeds → refresh the index. A small **`assetStore`** helper owns the copy/delete (the React analog of Swift's `CoverAssetStore`).
- Renderer: Add/Change → `pickImage` → `setBanner`; right-click → `bannerMenu` → change re-runs `pickImage`, remove clears the field. After a mutation the tree reloads and the banner re-renders.

## Testing

- **Main:** `assetStore` copy + delete-after-replace; the `setBanner` dispatch (writes the field, preserves loose/foreign keys, both owner kinds); the protocol's path-traversal guard + resolution; `readNexus` exposing `banner`.
- **Renderer:** the two `Banner` states and the pick → save → reload flow.
- Additive to the existing suite; no regressions.

## v1 non-goals (deferred)

- **View-level richness:** Homepage/Context widget regions — composed at the view level, a separate future design.
- **Page / Collection / Homepage wiring** — drop-in once their content views exist (Page uses a new frontmatter `banner`, distinct from `cover`).
- **Per-view "Display Banner" toggle** (Swift's `showBanner`) — React has no saved-view layer yet.
- **Crop / focal point** — aspect-fill only.
- **Migrating the nexus photo to `nexus-asset://`** — possible later, out of scope.

---

## Implementation Plan

Three phases, each a green commit (typecheck + tests pass). **DRY anchors:** one `Banner` component, one `setBanner` op, and one `DetailScaffold` serve every owner kind; the file-dialog and binary-write helpers are shared, never duplicated.

### Phase 1 — Data layer, storage & asset protocol (main)

- **Schema + types:** add `banner: z.string().optional()` to `pageTypeSidecar` and `contextBase` (area/topic/project inherit it). Add `banner: string | null` to the vault + context node types in `shared/types.ts`.
- **Banner asset I/O (inline in the `setBanner` case):** decode the data URL, derive `<ext>` from its mime, write `.nexus/assets/<id>/banner.<ext>` via the existing `atomicWriteBinary`, and clear any prior `banner.*` in that folder; removal deletes the file. No new module — it has one caller and mirrors the existing inline photo-save. The entity `id` comes from the sidecar we already load to write the field.
- **`setBanner` op:** `{ op: 'setBanner'; path; kind; dataUrl: string | null }` in `shared/mutate.ts`; dispatch in `main/mutate.ts` → with an image: write the asset (above) then set the sidecar `banner` field, deleting the prior file only after the field write succeeds; with `null`: clear the field then delete the file. Reuse the existing sidecar read/write + `refreshSessionIndex`. `kind ∈ 'pageType' | 'area' | 'topic' | 'project'` → `SIDECAR_FILENAME`.
- **`readNexus`:** set `banner` (the relpath, or `null`) on each vault + context node from its sidecar.
- **`nexus-asset://` protocol:** add the scheme to the existing `registerSchemesAsPrivileged([...])` array (top of `main/index.ts`, `{ standard, secure, supportFetchAPI, stream }`); add a `registerAssetProtocol()` `protocol.handle` call inside `.whenReady()` next to `registerRendererProtocol()`. It resolves `nexus-asset://nexus/<relpath>` under the session root, rejects anything outside `.nexus/assets/`, and returns the file. **No CSP work** — the app sets none today (images aren't blocked); if a CSP is ever added, include `nexus-asset:` in `img-src`.
- **Green:** assetStore save/replace/remove; `setBanner` dispatch (both kinds, field written, foreign keys preserved); protocol traversal guard; `readNexus` banner exposure.

### Phase 2 — Native pickers (main + preload)

- **`pickImage` (main):** native image file dialog → data URL or `null`. Factor the dialog body out of the existing `nexus:photoMenu` into a shared helper both reuse (no duplicated dialog).
- **`bannerMenu` (main):** `Menu.popup` with Change / Remove → `'change' | 'remove' | null` (mirrors the existing native photo menu).
- **preload:** bridge `pickImage` + `bannerMenu`.
- **Green:** typecheck; existing tests stay green.

### Phase 3 — UI (renderer)

- **`Banner` (+ css):** no-banner → slim strip, hover-revealed `plus` + "Add Banner" → `pickImage` → `setBanner`. Has-banner → `<img src="nexus-asset://…">` (180px, `object-fit: cover`) + name overlaid bottom-leading + right-click → `bannerMenu` → change/remove. Props `{ banner, entityId, kind, name }`.
- **`DetailScaffold` (+ `.detail` restructure):** full-bleed scroller + inner padded body (today's padding moves inward); banner slot at top, divider below. One component for every banner-bearing view.
- **Wire `DetailPane`:** route vault + context through `DetailScaffold`. A selection carries only an `id`, so resolve it to its node first — vault via the existing `findVault`, context via a small `findContext(id)` that scans areas/topics/projects and yields `{ path, kind, name, banner }` (the `kind` is whichever tier list held the id). Pass that to `DetailScaffold` / `Banner`. `none` / `page` unchanged.
- **Green:** typecheck + renderer tests (Banner states); then a visual check in the live dev app.
