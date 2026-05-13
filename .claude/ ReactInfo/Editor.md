### React Editor Reference

Editor surface for the React+Electron path: BlockNote and Tiptap as co-primary candidates, two-format serialization architecture, custom serializers for the two Pommora directives.

> **Status:** Reference document. Active stack is SwiftUI (Option 2 hosts the same JS editor in a WKWebView). This file documents the pure-React editor shape for translation reference.

---

#### Editor serialization architecture — Markdown on disk, JSON in-editor

The React editor uses **two serialization formats deliberately**, each chosen for what it does best. This is the editor's architecture, not a risk mitigation — both formats are first-class and Pommora needs both to function.

**Markdown (`.md` on disk) — canonical content format.**

- **Used for:** every Page's storage in the vault. The file is what an external agent reads, what Obsidian / GitHub / `cat` render, what `grep` searches. The third load-bearing constraint (persistent immediate legibility for agents) requires this.
- **API:** `blocksToMarkdownLossy(blocks?: Block[]): string` (write) and `tryParseMarkdownToBlocks(markdown: string): Promise<Block[]>` (read).
- **Carries:** standard Markdown (paragraphs, headings, lists, code blocks, images, GFM tables, blockquotes, horizontal rules) plus the two Pommora directives (`:::columns`, `:::callout`).
- **`Lossy` is a generic-API label, not a Pommora concern.** Pommora's content model is the standard Markdown set plus two well-defined directives (`:::columns`, `:::callout`); the per-block / per-node serializers below close that gap. Small, bounded code — quick fix at the boundary, not an ongoing risk.

**Working JSON state (in-memory) — editor state and perfect-fidelity export.**

- **Used for:** the editor's internal working state (always JSON in memory while editing), undo/redo history, debug snapshots, any case where perfect round-trip fidelity matters and Markdown can't carry it (selection ranges, in-flight transforms, Pommora-to-Pommora interchange).
- **API (BlockNote):** `editor.document` reads the block tree; `JSON.stringify` serializes it. **API (Tiptap):** `editor.getJSON()` reads the ProseMirror document as JSON; `editor.getHTML()` for the HTML form. Both are canonical stores; round-trip is exact by construction.

**Custom serializers for the two directives.**

- `:::columns` and `:::callout` get per-block / per-node markdown handlers. **BlockNote pattern:** `toExternalHTML` / markdown handlers per block spec ([Issue #221](https://github.com/TypeCellOS/BlockNote/issues/221) → [PR #426](https://github.com/TypeCellOS/BlockNote/pull/426)). **Tiptap pattern:** `renderHTML` per node + the first-party `@tiptap/markdown` extension's `MarkdownManager` (`editor.markdown.parse(md)` / `editor.markdown.serialize(json)` / `editor.getMarkdown()` / `editor.commands.setContent(md, { contentType: 'markdown' })`). Markdown round-trip is first-class — no extensibility hooks or parallel `prosemirror-markdown` wiring required.
- These bridge the in-memory JSON representation of Pommora's directives to their Markdown form on disk. Without them, the directives fall back to the editor's default serialization on save.
- Two block / node types, two pairs of handlers — small, well-bounded code surface, not an open-ended serializer burden.

**Why both formats are necessary:**

- Markdown alone can't carry editor state (cursor positions, selection ranges, in-flight operations, undo stack). The editor needs a richer working format.
- JSON alone breaks agent-legibility, external-tool compatibility, and vault portability. Pages must be Markdown on disk.
- Custom serializers alone don't help if the editor can't represent the directives internally; they're the boundary code, not the working format.

The Markdown ↔ JSON split is deliberate, not a workaround. Treat it as a load-bearing architectural detail of the React path.

**If the BlockNote / Tiptap block UX fails to land as wanted** (unlikely — both are mature implementations of the Notion-style pattern), Milkdown (markdown-first; ProseMirror foundation) or CodeMirror 6 (buffer-based; markdown literally *is* the document) remain in the catalog. Both trade the Notion-style block UI for a different editor model — the opposite tradeoff from what React wants. The Markdown ↔ internal-state architecture survives the pivot; only the API names and the boundary code change.

---

#### Editor strategy

**Co-primary candidates (if React + Electron is picked) — pick at commit time:**

- **BlockNote (MPL-2.0)** — batteries-included block editor built on Tiptap; slash menu, formatting toolbar, drag handles, schema enforcement all wired by default. Faster to a working editor; less ceremony for custom blocks. License caveat on the XL packages (`@blocknote/xl-multi-column` is GPL-3.0 OR a paid commercial Business subscription — pricing not pinned in docs, verify on blocknotejs.org/pricing; build the multi-column block in core to avoid the question entirely).
- **Tiptap (MIT)** — headless editor framework; the underlying primitive BlockNote is built on. Every package Pommora would use (`@tiptap/core`, `@tiptap/react`, `@tiptap/extension-drag-handle-react`, `@tiptap/markdown`, etc.) ships under MIT from the regular `@tiptap/*` npm scope. Trades batteries for full configurability — slash menu, formatting toolbar, drag handles are wired explicitly.

Either editor delivers the same wanted UX:

- Keep per-paragraph `+` insertion markers and drag-handle (grip) markers on the left of every block — they're the wanted Notion-style affordance, how you insert directives and reorder paragraphs without diving to a menu. The on-disk format stays continuous Markdown; the block UI is purely the editing surface.
- Custom block / node specs for `:::columns` and `:::callout` (BlockNote: `createReactBlockSpec`; Tiptap: `Node.create` with a React node view). Blockquotes use standard `>` syntax via the built-in blockquote node, with Pommora's distinct visual styling (filled background + left-side emphasis bar via `blockquote//` tokens). Callouts are a distinct construct with their own custom spec / node (outlined box; `callout//` tokens).
- Build the multi-column block in-tree on BlockNote (don't pull `@blocknote/xl-multi-column`, which is the one copyleft-or-commercial BlockNote package); on Tiptap, build it as a custom node directly — no comparable package to avoid
- Custom markdown serializer per block / node type to enforce files-canonical round-trip
- Wikilinks render as styled colored inline text via custom inline marks; pair with `@flowershow/remark-wiki-link` for the parse direction
- Slash menu, bubble toolbar, undo / redo, copy / paste, keyboard shortcuts, content schema enforcement — built-in on BlockNote, wired explicitly on Tiptap

**Pivot doors held open** (in order of decreasing similarity to BlockNote / Tiptap):

- **Milkdown** — markdown-first by design (round-trip integrity built into the framework); MIT; ProseMirror foundation. Plugin ecosystem includes slash, history, clipboard, listener, prism, math, emoji, upload, tooltip.
- **Yoopta** — Slate-based; MIT; 20+ built-in plugins including a callout.
- **CodeMirror 6** — buffer-based; perfect markdown round-trip by construction; meaningfully more work to layer Notion-style block UI on top (its strength is the markdown-as-document model, the opposite tradeoff from what React wants).

---

#### Verified library findings

- **BlockNote (MPL-2.0) and Tiptap (MIT)** are the two co-primary editor candidates — both ProseMirror-based, both fully open-source and free for Pommora's scope, either able to deliver the **wanted Notion-style block editor surface**: per-paragraph `+` (insert) and drag-handle (reorder) markers on the left, slash menu, formatting toolbar, custom blocks for `:::columns` / `:::callout`, markdown round-trip. The block UI is a wanted feature on React — the affordance for inserting directives, reordering paragraphs, and anchoring focus visually — sitting on top of an on-disk continuous Markdown stream. BlockNote is the higher-level / batteries-included option (it's literally built on top of Tiptap); Tiptap is the lower-level / fully-configurable option. Pick at React commit time. Pivot doors (only if the block UX disappoints): Milkdown (markdown-first by design), Yoopta (Slate-based), CodeMirror 6 (markdown-canonical Plan B).

- **`remark-directive` + `mdast-util-directive`** for `:::columns` and `:::callout` directives. Container directives have a clean AST and `directiveToMarkdown()` round-trips them back to `:::` syntax. Nesting requires the outer fence to use more colons (`::::columns` containing `:::callout`) to avoid ambiguous closes. (Blockquotes use standard `>` syntax — not a directive. Callouts are now a distinct construct with their own directive, not a styled blockquote.)

- **`@flowershow/remark-wiki-link` v3.3.1+** for Obsidian-flavored wikilinks: `[[name]]`, `[[name|alias]]`, `[[name#heading]]`, combined `[[name#heading|alias]]`, and `![[asset]]` embeds with dimensions. Healthiest of the maintained options.
