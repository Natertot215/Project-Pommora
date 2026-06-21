## Editor — Pages & the Deferred Block Editor

Light reference for the editing surface. Two distinct editors; don't conflate them.

### Core Pages editor — Markdown is the document

Pages are Markdown on disk. The editor edits Markdown directly (frontmatter ↔ body) with Pommora's rendering directives — it is **not** a block editor.

- **Decided: build our own.** The exact build spec is `Planning/MarkdownPM.md` — a faithful behavioral port of the Swift `MarkdownPM` package. We own the **behavior layer** (dynamic syntax, detection, styling, input transforms, theme) 100%; the two places Swift leaned on the platform get one swappable dep each, behind a seam: **CodeMirror 6** as the text substrate (the TextKit analog — buffer-based, Markdown *is* the document) and **micromark/mdast** as the GFM AST (the swift-markdown analog). Neither is installed yet.

### Deferred block editor — Contexts-as-blocks + Homepage

Net-new vs. Swift; out of scope until the frontier. A Notion-style block surface (per-block `+` / drag handles) over content that still serializes to Markdown/JSON.

- **Candidates:** BlockNote (batteries-included, built on Tiptap) · Tiptap (headless, MIT) · Milkdown (markdown-first) · Yoopta (Slate-based). Pick at build time.
- **`react-grid-layout`** is the candidate for the 2-D dashboard composition (Homepage) — see `Libraries.md`.

### Boundary concerns (whichever editor)

- **Two formats, on purpose:** Markdown on disk (canonical, agent-legible); editor state in memory (JSON / buffer). Custom serializers bridge the two Pommora directives — `:::columns`, `:::callout` — so they round-trip to Markdown rather than the editor's default form.
- **Wikilinks** render as styled colored inline text (not chips); pair a custom inline mark with `@flowershow/remark-wiki-link` for parsing.
