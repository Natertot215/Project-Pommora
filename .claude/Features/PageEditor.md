### Page Editor

Pommora's body editor for Pages — what the user sees and types into when they open a Page. Data-model concerns (on-disk shape, frontmatter, opening behavior, sidebar disclosure) live in [[Pages]]; this file covers the editor surface. The construct-level contract — dynamic-syntax architecture, detection rules, state-mutation guards, anti-patterns, engine quirks, and every locked editor decision — lives in [[MarkdownPM]]; read it first when implementing any construct. This spec records WHAT the editor ships and its visible surface.

---

#### Architecture

The editor is a native TextKit-2 stack with a clear division of labor, each layer hot-swappable behind a stable boundary:

- **Parser** — Apple's `swift-markdown` contributes a full GFM AST.
- **Renderer** — Apple's `NSTextView` on TextKit 2, styling an `NSAttributedString`. Selection, find, native context menu, Writing Tools, spell-check, autocorrect, IME, and drag-select all come for free from the system text view.
- **Live-preview chassis** — `MarkdownPM`, the Pommora-owned Swift package maintained in-tree, supplies the two things a bare text view lacks: **dynamic syntax** (a construct's markers shrink when the caret leaves its AST node and expand when it enters) and **Markdown-aware typing helpers** (list continuation, block auto-wrap, character-pair auto-pairing).
- **Supplemental styling** — a caret-unaware AST pass styles the constructs the primary per-construct pass doesn't own, composed last so it wins on overlap.
- **Domain wiring** — page references, file model, content-manager update path, editor view-model and host, inspector and sidebar wiring — all editor-library-agnostic.

**Hot-swap boundary.** The swap surface is the editor call site plus the Pommora customizations inside `MarkdownPM` (the supplemental styler and the input-handler / layout / context-menu extensions). The `.md` format, the view-model-to-content-manager chain, and the atomic-write contract are all library-agnostic — replacing the editor engine touches none of them.

---

#### Layout

The view stacks two top-leading-aligned layers:

1. **Body editor** (bottom) — the `MarkdownPM` front-door view. Horizontal text inset aligns body text under the title's padding; a larger top inset reserves a scrollable empty zone for the title overlay.
2. **Title + divider overlay** (top) — a large-bold plain title field matched to macOS Notes, above a hairline separator. The overlay tracks body scroll, so the title scrolls in sync and moves off-screen once scrolled past. Enter commits the rename and hands focus to the body.

**Page icon.** When the per-Nexus show-page-icon setting is on (default off), the frontmatter icon renders inline to the left of the title on the baseline (tap to change or remove); with no icon set, hovering reveals a faint "Add Icon" affordance. Off or unset leaves the title flush-left with no reserved indent. The same icon propagates to the sidebar row and Navigation, overriding the per-kind default.

The inspector and its toolbar toggle live in `ContentView`, so the inspector renders at the window's trailing edge rather than inside this sub-view. A cover or banner drops into the overlay stack above the title with no engine changes. The titlebar carries no properties pulldown — page properties surface through the pop-out inspector (frontmatter properties are its only content today). A Claude chat interface in the inspector is a [[Prospects|Prospect]].

---

#### Save pipeline (preserves "files are canonical")

Keystroke → body change → short debounce → content-manager update path → reconstruct the page file (frontmatter + body + title) → atomic write (temp-file then rename) → in-memory cache update. The pipeline flushes on every context loss: page-switch (the host awaits the outgoing page's close), window-close, app resign-active, app terminate, and explicit save.

**Frontmatter preservation.** The editor binds ONLY to the body — pure Markdown, with YAML stripped on load before it reaches the editor. Frontmatter is held on the view model and re-serialized on save from the typed struct, never from a string prefix. The user cannot destroy frontmatter through the editor, and YAML is never visible.

**Failure handling.** A pending-error alert (Retry / OK) preserves the draft body; retry re-schedules the write.

**Editable title.** The title field is structurally separate from the body. On Enter it drops its first-responder claim cleanly (otherwise the field selects-all and stays focused), moves focus to the body's text view, and commits the rename asynchronously in parallel — an on-disk file move plus cache refresh — without blocking the focus shift. A failed rename (e.g. a name collision) fires the pending-error alert and reverts the title draft.

---

#### Current editor surface

**Inline marks** (emphasis locates on the AST, other constructs on regex; caret-aware marker-shrink): bold, italic, bold-italic, inline code; standard Markdown links; image embeds (render hook present, image provider deferred). Connections (`[[Name]]` / `{{Name}}`) are a **body construct** — inline styled colored text in the Markdown stream, click resolution pending the Pommora-side resolver; distinct from context-link properties (see [[Pages]]).

**Block constructs** (engine + supplemental):
- **Headings** on a Pommora scale descending from a large H1 to body size at H6 (nothing renders below body size); only H1–H4 are offered in the right-click menu. **Foldable** — hovering a heading reveals a gutter chevron that collapses the section to the next equal-or-higher heading (or document end); fold state persists per-Page in frontmatter.
- **Lists** — bullet and ordered, with portable CommonMark source; a bullet glyph renders over the source dash while disk source stays portable.
- **Task checkboxes** — GFM source. The fast no-space shorthand is canonicalized to GFM on input the moment the content-starting space is typed (caret lands after the trailing space so typing flows on), keeping the quick entry while writing portable, Obsidian-renderable source. A symbol glyph draws in place of the bracket marker; clicking it toggles the source.
- **Fenced code blocks.**
- **LaTeX** (inline and block) — marker-shrink ships; math rendering deferred.
- **Blockquote** — grey-tint rounded card with a continuous accent bar; multi-paragraph quotes join contiguously. Enter continues, Shift+Enter exits.
- **Strikethrough.**
- **Table** — GFM source parses and styles (monospace, faint background, pipes and separator row hidden); the rich inline-grid editing UX is paused (see below).
- **Thematic break** — renders as a rule when the caret is off the line and reverts to literal source for editing when entered; the Setext-heading interpretation is rejected.

**Typing helpers:** list continuation (Enter auto-fills the next marker, preserving indent and checkbox); block auto-wrap (block constructs stay on their own line); character-pair auto-pair and auto-delete (single bracket only auto-pairs at whitespace or line start so the checkbox shorthand flows); bracket-skip on Enter; dash and arrow auto-format (input-time only — paste preserves literal text).

**Right-click menu** (engine base + Pommora extensions): the standard system entries plus Format, Heading (H1–H4), Lists, and Block submenus.

**System integration** (free via the text view): Writing Tools, Look Up, Translate, spell/grammar/autocorrect with per-token suppression for code and LaTeX, IME, dynamic light/dark colors, drag-to-select. The find-highlighting bus is present; the Pommora-side find palette is deferred.

**Stats footer:** a hover-revealed chevron at the bottom-right toggles a thin bar — a Finder-style `Collection › Set › Page` breadcrumb on the left, line/word/character counts on the right. Lines count raw source; words and characters count rendered prose (syntax stripped, structural separators excluded). Counts compute only while open, debounced. Open state persists globally. Clickable breadcrumb navigation was tried and dropped (it routed into detail surfaces where the editor isn't wired).

---

#### Tables — to be implemented

Apple-Notes-style inline-grid tables — drag-resize columns, a double-click popover cell editor, and a structural context menu for add/delete row-column plus cell alignment — are a named roadmap deliverable. Today GFM source parses and renders styled, with no grid alignment or editing affordances.

**Open question — inline-column alignment.** Laid out as inline text, cells don't visually align unless the source is padded to equal column widths. A dedicated text-table primitive is rejected — it forfeits Writing Tools, Look Up, and dynamic color and forces a TextKit-1 downgrade. The intended direction keeps disk source uniformly padded, stores column widths in frontmatter, and has the render layer apply overrides; making inline layout honor custom widths is the unsolved part. The popover editor and structural menu don't depend on it and can land independently. The table-widths frontmatter key is grandfathered and renames when Tables ship.

---

#### Deferred

- **Wikilink resolver** — unblocks click routing and rename cascade.
- **Callout and column directives + slash menu** — via Apple block directives.
- **Syntax-highlighting and LaTeX-rendering bridges** — no-op defaults ship; both opt-in.
- **Image embed provider.**
- **Find-in-document UI** — over the existing find bus.
- **Auto-pair polish** — selection-wrap and auto-exit-on-whitespace.
