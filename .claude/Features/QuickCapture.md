### Quick Capture

> A lightweight surface for adding **Pages, Tasks, and Events** from outside the main window — a menu-bar pane on the Mac, optionally fed by a web-clip route. Concept + architecture doc, not a wiring plan; roadmap slot in `Framework.md`.

#### What it is

A small single-pane entry point — think Things 3 / Drafts / a web clipper — that creates an operational entity directly into the nexus without opening the full app. It is **another entry point on the existing data layer, not a new feature stack**: it reuses the same create operations and property-assignment UI as the main app.

Three capture kinds: **Page** (scoped to a Vault, optionally a Collection), **Task**, **Event**. Tasks and Events are top-level (no container to pick). Capture is title + properties first — not a body editor; prose continues in the main window.

#### Foundational principle — single-owner nexus access

The capture surface must never become a second writer. The Pommora app is the **sole owner** of nexus access — the security-scoped folder grant, the SQLite index, the atomic writes. Quick Capture is therefore a *view inside the app process*, not a separate binary:

- It reuses the live managers, the resolved nexus, and the open index directly — no second permission grant, no cross-process DB coordination.
- Any external source (browser extension, system Share sheet) acts as a **courier**: it gathers a payload and hands it to the running app, which performs the write. The courier never touches the nexus.

Presenting it as a menu-bar utility is a *presentation* choice, separate from this *ownership* choice — conflating the two is what would turn a small feature into a large one.

#### Why the data layer already supports it

- **Create is file-canonical.** A Page writes its `.md`; a Task / Event writes its `.task.json` / `.event.json`. The write is atomic and the index upsert is best-effort, so capture succeeds at the file level even if the index lags. (→ [[Architecture]].)
- **The property UI is host-agnostic.** The property panel takes a schema + value bindings, not the manager graph, so the same surface renders in a compact pane. (→ [[Properties]].)

#### Capture flow

1. **Pick kind + scope.** Page → Vault (optionally Collection); Task / Event → top-level.
2. **Fill the entity.** Title + property fields for that Type.
3. **Save.** Lands in the nexus immediately.

Title + Icon show first (universal across all three); location + properties fill in once a kind is picked. A Type can carry many properties, so the pane shows a compact subset with a `…` **"show all"** affordance revealing the full schema on demand. What defines the subset is open — the original pinning mechanism no longer exists (→ [[Prospects]]); declaration order is the fallback.

#### Web capture (browser / share sheet)

Extends naturally to web clipping — a page's **title, URL, description, and selected text** into a new Page (e.g. a Bookmarks Vault) or a Task / Event. The capturer is always a courier. Candidate routes, chosen at spec time, can coexist:

- **Browser extension via native messaging** — the established web-clipper pattern (Obsidian, Notion, Raindrop). Most seamless; most setup.
- **System Share Extension** — Apple-native: Share sheet → "Add to Pommora," reachable anywhere, no browser toolchain.
- **Custom URL scheme** (`pommora://capture?…`) — simplest bridge, least polished.

#### Apple surfaces in play

- **`MenuBarExtra`** with `.menuBarExtraStyle(.window)` — the popover-style pane, coexisting with the main window.
- **Agent app (`LSUIElement`) + `SMAppService`** — keeps the pane available from the menu bar even when the main window is closed, no Dock icon.
- **Native Messaging / Share Extension / App Intents** — the external routes; App Intents is a cheap bonus ("Add to Pommora" as a Shortcut / Spotlight action).
- **EventKit** underlies the Task / Event capture targets.

#### Deferred / open

- **Body capture** — whether the pane grows a body field is a spec-phase call.
- **Capture while fully quit** — available whenever the app (including as a launch-at-login agent) runs; a headless daemon would reintroduce the multi-process problems this design avoids, so it's not planned.
- **Which web route ships first** — a spec-phase scope call.
- **Context-link fields** — pickers depend on the index + resolver; keeping tier fields behind "show all" keeps capture fast.
