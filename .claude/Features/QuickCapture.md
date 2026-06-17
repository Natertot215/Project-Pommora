### Quick Capture

> A lightweight surface for adding **Pages, Agenda Tasks, and Agenda Events** to the nexus from outside the main window — a menu-bar pane on the Mac, optionally fed by a browser/web-clip route. This is a concept + architecture doc, not a wiring plan. Roadmap slot lives in `Framework.md`.

#### What it is

Quick Capture is a small single-pane entry point — think Things 3 / Drafts / a web clipper — that creates an operational entity directly into the nexus without opening the full app. It is **another entry point on the existing data layer, not a new feature stack**: it reuses the same create operations and the same property-assignment UI as the main app.

Three capture kinds at launch: **Page** (scoped to a Vault, optionally a Collection), **Agenda Task**, and **Agenda Event**. Tasks and Events are top-level capture options (no container to pick). Capture is title + properties first — the pane is not a body editor; prose continues in the main window.

#### Foundational principle — single-owner nexus access

The capture surface must never become a second writer to the nexus. The Pommora app is the **sole owner** of nexus access — the security-scoped folder grant, the SQLite index, the atomic file writes. Quick Capture is therefore a *view that runs inside the app process*, not a separate helper binary:

- It reuses the live managers, the resolved nexus, and the open index directly — no second folder-permission grant, no cross-process database coordination.
- Any external capture source (a browser extension, the system Share sheet) acts as a **courier**: it gathers a payload and hands it to the running app, which performs the actual write. The courier never touches the nexus itself.

This keeps the "files are canonical, one process owns the index" model intact and makes Quick Capture a thin surface rather than a parallel app. Presenting it as a menu-bar utility is a *presentation* choice (see Apple surfaces), separate from this *ownership* choice — conflating the two is what would otherwise turn a small feature into a large one.

#### Why the data layer already supports it

- **Create is file-canonical.** Creating a Page writes its `.md` file (YAML frontmatter + body); a Task / Event writes its `.task.json` / `.event.json`. Either way the write is atomic and the SQLite index upsert is best-effort and non-fatal — so capture can always succeed at the file level even if the index lags. (→ [[Architecture]].)
- **The property-assignment UI is host-agnostic.** The property panel and per-property editors take a schema + value bindings, not the manager graph — so the same editing surface renders in a compact capture pane. (→ [[Properties]].)

#### Capture flow

1. **Pick the kind + scope.** Page → choose Vault (and optionally a Collection); Task / Event → top-level, no container.
2. **Fill the entity.** Title + the property fields for that Type.
3. **Save.** The entity lands in the nexus immediately.

**Compact-schema display.** A Type can carry many properties; showing all of them would bury the fast-capture intent. The pane shows a compact subset first, with a small `…` affordance beneath the list to **"show all"** — revealing the full schema only on demand. What defines the subset is open: the original design leaned on a property-pinning mechanism that no longer exists (→ [[Prospects]] § "Pinned-property zone for the PagePreview card"); declaration order is the fallback.

Title + Icon display before a Page, Task, or Event designation is given since those are universal across all three; the specific location + properties display as fill-ins once a selection is made. Capture could also omit Tasks + Events for an even cleaner flow, capturing Pages only.

#### Web capture (browser / share sheet)

Quick Capture extends naturally to web clipping — capturing a page's **title, URL, description, and any selected text** into a new Page (e.g. a Bookmarks Vault) or a Task / Event. The capturer is always a courier (per single-owner access). Candidate routes, to be chosen at spec time:

- **Browser extension (e.g. Chrome) via native messaging** — the established web-clipper pattern (Obsidian Web Clipper, Notion, Raindrop). Most seamless for browser capture; most setup.
- **System Share Extension** — an Apple-native path: the macOS / Safari Share sheet → "Add to Pommora," reachable from anywhere, no browser-specific toolchain.
- **Custom URL scheme** (`pommora://capture?…`) — the simplest bridge; less polished than native messaging.

These are alternatives, not all-or-nothing — a Share Extension and a browser extension can coexist.

#### Apple surfaces in play

- **`MenuBarExtra`** (SwiftUI, macOS 13+) with `.menuBarExtraStyle(.window)` — the popover-style capture pane; coexists with the main window in the same app.
- **Agent app (`LSUIElement`) + launch-at-login registration (`SMAppService`)** — keeps the capture pane always-available from the menu bar even when the main window is closed, without a Dock icon.
- **Chrome Native Messaging / Share Extension / App Intents** — the external capture routes; App Intents is a cheap bonus ("Add to Pommora" as a Shortcut / Spotlight action) on the same create operations.
- **EventKit** (the Agenda work) underlies the Task / Event capture targets.

#### Deferred / open

- **Body capture** — whether the pane ever grows a body field, or stays title + properties with prose continuing in the main window, is a spec-phase call.
- **Capture while the app is fully quit** — the in-app menu-bar surface is available whenever the app (including as a launch-at-login agent) is running; a truly headless capture daemon would reintroduce the multi-process problems this design avoids, so it is not planned.
- **Which web route ships first** (browser extension vs Share Extension) — a UX / scope call for the spec phase.
- **Context-link fields in the capture pane** — context pickers (`ContextPicker`) depend on the index + a resolver; keeping tier-relation fields behind "show all" keeps capture fast.
