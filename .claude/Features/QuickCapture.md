### Quick Capture

A lightweight surface for adding **Pages, Tasks, and Events** from outside the main window — the menu-bar or global-shortcut entry point in the Things 3 / Drafts idiom. It's another entry point on the existing data layer — it reuses the same create operations and property surfaces as the main app.

Three capture kinds: a **Page** (scoped to a Collection, optionally a Set), a **Task**, and an **Event**. Tasks and Events are top-level with no container to pick. Capture is title-and-properties first, not a body editor — prose continues in the main window.

### Features

#### II. Single-Owner Principle

The app is the **sole owner** of Nexus access — the folder grant, the index, the atomic writes. Quick Capture is therefore a surface inside the app process, not a second binary: it reuses the live data layer and the open index directly, with no second permission grant and no cross-process coordination. Any external source — a browser extension, a system share — acts as a **courier**: it gathers a payload and hands it to the running app, which performs the write. The courier never touches the Nexus.

#### II. Capture Flow

1. **Pick kind and scope** — a Page picks its Collection (optionally a Set); a Task or Event is top-level.
2. **Fill the entity** — a title plus the schema's property fields, shown as a compact subset with a "show all" affordance since a Collection can carry many.
3. **Save** — the entity lands in the Nexus immediately.

#### II. Web Capture Routes

Capture extends to web clipping — a page's title, URL, description, and selected text into a new Page (a Bookmarks Collection, say) or a Task / Event. The clipper is always a courier handing its payload to the running app. Candidate routes can coexist: a browser extension over native messaging, a system share target, or a `pommora://capture?…` URL.

### Pending

**The Entry Surface:** Quick Capture is unbuilt — there's no capture pane and no global entry point. The Electron entry surface is the open design decision: a global shortcut, a tray-based popover (heavier than a native menu-bar item), or a launch-at-login background agent, paired with the web-capture courier route. Capture while the app is fully quit stays out of scope — a headless writer would reintroduce the multi-process problems the single-owner principle avoids.
