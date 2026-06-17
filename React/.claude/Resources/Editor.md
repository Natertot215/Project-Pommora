## Editor — Pages & the Deferred Block Editor

Light reference for the editing surface. Two distinct editors; don't conflate them.

### Core Pages editor — Markdown is the document

Pages are Markdown on disk. The editor edits Markdown directly (frontmatter ↔ body) with Pommora's rendering directives — it is **not** a block editor.

- **Strongly consider building our own.** The Swift build's **MarkdownPM** package (TextKit 2 + Apple `swift-markdown`) already describes the exact behavior and functionality Pommora wants — it's a proven behavioral spec, not a library to go shopping for. The React editor can port that behavior rather than bending a third-party framework to fit it. Behavioral reference: the Swift project's `Features/PageEditor.md` + `MarkdownPM`.
- **If adopting instead of building:** **CodeMirror 6** is the Framework's candidate — buffer-based, where Markdown literally *is* the document (the right model for a Markdown-canonical editor). Not yet installed.

### Deferred block editor — Contexts-as-blocks + Homepage

Net-new vs. Swift; out of scope until the frontier. A Notion-style block surface (per-block `+` / drag handles) over content that still serializes to Markdown/JSON.

- **Candidates:** BlockNote (batteries-included, built on Tiptap) · Tiptap (headless, MIT) · Milkdown (markdown-first) · Yoopta (Slate-based). Pick at build time.
- **`react-grid-layout`** is the candidate for the 2-D dashboard composition (Homepage) — see `Libraries.md`.

### Boundary concerns (whichever editor)

- **Two formats, on purpose:** Markdown on disk (canonical, agent-legible); editor state in memory (JSON / buffer). Custom serializers bridge the two Pommora directives — `:::columns`, `:::callout` — so they round-trip to Markdown rather than the editor's default form.
- **Wikilinks** render as styled colored inline text (not chips); pair a custom inline mark with `@flowershow/remark-wiki-link` for parsing.
