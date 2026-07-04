## Mobile — Form Factor

How Pommora's three-pane desktop shell becomes a phone. Structural and interaction decisions live here; the pixel-level look is a Figma pass.

### The Shell — One Pane, Two Swipe-In Drawers

The desktop's three panes (sidebar / main / inspector) can't sit side by side on a phone. They collapse to one center pane with two drawers: swipe right to reveal the **sidebar** (browse), swipe left to reveal the **inspector** — each sliding over or pushing the center pane aside, the pattern every mobile LLM app uses. The center pane holds one entity at a time: a Page in the editor, the Homepage, or a Context.

The drawer is a maintained edge-swipe primitive or a small gesture-plus-motion build that reuses Pommora's single motion source rather than importing a second animation engine — Interaction.md is the law, and the drawer mounts to it. Edge-swipe arms only from a screen-edge hit-zone so it never competes with content gestures. Safe-area insets (notch, home indicator) are handled with the standard viewport-cover meta plus inset variables — no plugin needed on iOS.

### Navigation — Sidebar Drill-Down Only (v1)

Reaching a page is the sidebar tree: expand a Collection, tap a Page, the center pane routes to it. Tapping a Collection or Set discloses it in the sidebar rather than filling the center — with container views deferred, the tree is the browse surface. Anything richer (Pinned/Recents, a history surface, tabs) waits until the desktop's own navigation is built, so the phone never gets ahead of the desktop.

With container views deferred and navigation limited to the tree, **finding a known page by tap-expanding is slow on a large nexus** — so a global search / quick-open is the one navigation affordance worth pulling forward, even a minimal title search. Flagged as a v1 consideration, not yet scoped.

Sidebar reorder and reparent stay drag gestures on touch — a long-press arms the drag so a plain swipe still scrolls the tree. The desktop's drag models are reused; only the touch activation differs.

### Editing — MarkdownPM on Touch

Page editing runs the same CodeMirror editor in the WebView, adapted to touch — a keyboard-accessory toolbar, keyboard and caret handling, input tuning, and selection care. It is its own workstream with its own doc: `MobilePM.md`.

### Quick Capture — a Button and a Shortcut

Capture is a lightweight create action, not the desktop's courier apparatus: a corner button that makes a Page, Task, or Event, plus an Apple Shortcut entry for capture from outside the app. In-app, the button writes through the running app's normal path. The Shortcut is the subtle case: an App Intent runs in a **separate system process while the app may be quit**, and the in-process write lock does nothing across processes — so it must not write the nexus directly. It either **queues the capture to an app-group location the running app drains** on next launch, or **launches the app to perform the write**. This keeps the desktop's single-owner rule (no headless writer racing the app), which a naive "write a file straight from the Shortcut" would break. Captured Tasks and Events land in the nexus; a surface to view them arrives with the Agenda work.

### The Inspector — a Reserved Multi-Tab Surface

The inspector is a core surface and ships on the phone as the right-hand drawer, but its *content* is its own brainstorm — a multi-tab contextual pane (per-page properties and outline, open-tabs and recents, pinned pages, future Agenda lists, and the Claude chat). The mobile shell reserves the drawer; the tabs and the chat mechanism are the inspector's own design pass. Any properties shown here are the same frontmatter a page's own properties surface shows — a panel that *displays* properties, not a place they live.

### Mobile-Only Liquid Glass

The phone can carry a **Liquid Glass** treatment the desktop doesn't — scoped to the **bottom toolbar and simple interface buttons**, never a wholesale reskin. Because the bottom toolbar is a mobile-only surface, its glass is inherently mobile-only. The approach splits by what each surface needs:

- **The bottom bar takes real iOS 26 system glass** through a native overlay — a native tab/tool bar rendered over the WebView by a Capacitor native-navigation plugin that opts into the system Liquid Glass material. This is the only route to authentic system glass (real environmental refraction, the exact Apple look) without private APIs. The web layout reserves the bar's height as a safe-area inset, and native taps bridge back to the router.
- **Loose buttons stay in the WebView** on Pommora's existing Liquid Glass Controls material, which refracts the element through an SVG filter. It ships Safari workarounds but sets a `backdrop-filter: url()` WebKit may not fully honor, so it needs on-device verification and a flat-fill fallback before it's relied on. At button scale the look is otherwise indistinguishable; the cost stays down by keeping glassed elements small and few.

Reaching for the real system glass *directly in web CSS* is a dead end — the property exists but is private API and an App Store rejection. A flourish, logged as its own small design direction, not a v1 blocker.
