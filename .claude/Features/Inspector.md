### Inspector

The trailing pane of the three-pane shell — a full-height panel beside the main content, drag-resizable with a persisted width and a global show/hide toggle.

The inspector is a wired shell: it opens, resizes from its leading edge, and animates the toolbar's control cluster onto its edge as it slides in, but its body renders nothing. It's reserved for the **Claude chat** — a frontend to a local CLI, not an API integration. Properties deliberately don't live here; they live with the content (→ `Properties.md`).

### Pending

**Inspector Content:** The inspector's content is an open design surface awaiting its own brainstorm. The Claude-chat frontend is the intended direction. The panel chrome — the toggle, the edge-resize, the glass material, and the control-cluster animation on open — is built; the body is empty.
