## UI Copy

### No Meta-Commentary in the UI — HARD Rule

The running app never displays build-status or meta text. No "— pending," no "coming soon," no "designed in Figma," no placeholder captions of any kind. An unbuilt pane or section renders **blank** — its chrome (TopRow, separator) may exist, its body simply holds nothing.

**Why:** Pommora is Nathan's daily driver; status captions are developer notes leaking into a product surface. The build's state lives in the docs (`Features/*` Pending sections), never in the render.

**How to apply:**

- A navigable-but-unbuilt destination ships its header/back chrome over an empty body.
- Genuine runtime states are NOT meta-commentary and keep their copy — errors ("Schema unavailable.") and true empty-DATA states (an empty search result). "…yet"-style captions describe the build, not the data — they're meta and they blank.
- Sweep for `— pending` style captions whenever touching a pane; blank them on contact.
