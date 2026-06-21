# MarkdownPM Manual Test

The full human-driven acceptance pass for the editor. Run it in the live app (`npm run dev`, open a page) after the review fixes land. Each case is written as **what you type / do** → **what you should see**. Type the way a person actually does — character by character, then click away, then click back in.

Two conventions:
- **caret-out** = click somewhere else on the line / another line (the marker syntax should hide and the styled form show).
- **caret-in** = click *into* the styled text (the raw `**`/`#`/`>` syntax should reveal so you can edit it).
- ⟐ marks a case that specifically validates a **review fix** — note the post-fix expectation.

---

## A. Inline Marks

- [ ] Type `**bold**`, caret-out → **bold** in bold weight; the `**` pairs hidden.
- [ ] Click into "bold" (caret-in) → both `**` pairs reveal as editable text.
- [ ] Type `*italic*`, caret-out → *italic*; single `*` hidden. Caret-in → `*` reveals.
- [ ] Type `***both***`, caret-out → bold **and** italic on "both".
- [ ] Type `**a *b* c**`, caret-out → "a b c" bold, with "b" additionally italic (one bold span, nested italic).
- [ ] Type `~~gone~~`, caret-out → ~~strikethrough~~ on "gone".
- [ ] Type `` `code` ``, caret-out → `code` in monospace with the code chip background.
- [ ] Type `` `*a*` `` → the `*a*` inside the code span stays literal (no italic — emphasis never fires inside inline code).
- [ ] ⟐ Type a marker then bold right after it (e.g. `- **x**`) → after the fix, the bold renders and the `-` marker does **not** corrupt it (no raw `**` leaking next to the marker).

## B. Bullet Lists

- [ ] Type `- item` → a `•` glyph in the gutter; "item" sits flush in the text column.
- [ ] ⟐ Click **into** the marker zone / just after the `•` → the caret enters; the `-` is editable source (post-fix: markers are editable transparent text, not an atomic block).
- [ ] ⟐ Type `- ` then keep typing `hello` → flows normally, no swallowed character, caret never gets shoved out.
- [ ] Press **Enter** at the end of "- item" → a new `- ` bullet on the next line, same indent.
- [ ] On an empty `- ` press **Enter** → continues another `- ` (Shift+Enter is the only exit).
- [ ] Press **Shift+Enter** on a bullet line → a plain newline (exits the list).
- [ ] At the **start of the content** (caret right after `- `), press **Backspace** → the whole `- ` marker is deleted in one step, caret to line start (not nibbled into broken syntax).
- [ ] `* item` and `+ item` → read as list lines, but only `-` substitutes the `•` glyph (`*`/`+` keep their literal marker).

## C. Ordered Lists

- [ ] Type `1. first` → "1." shown literally (visible source, tabular figures), "first" in the text column.
- [ ] Press **Enter** at the end → `2. ` opens on the next line (auto-increment).
- [ ] ⟐ Type `1.` then a **space** then `word` → the space lands normally and "word" is editable; nothing is swallowed and no bold-reveal glitch (this is the headline bug — must be clean post-fix).
- [ ] ⟐ Click into the `1.` and edit it to `5.` → editable as plain source text.
- [ ] `12. x` → multi-digit marker renders and aligns (periods line up down the column via tabular-nums).

## D. Task Checkboxes

- [ ] Type `- [ ] task` → an empty chip checkbox in the marker zone; "task" in the text column.
- [ ] Type `- [x] done` (or `[X]`) → a filled (accent) checkbox; "done" as content.
- [ ] **Click** the checkbox → toggles the source `[ ]` ↔ `[x]` in one undoable step (⌘Z restores).
- [ ] Type the shorthand `-[]` then a **space** → canonicalizes to `- [ ] ` with the caret after the trailing space (typing flows straight into the task text).
- [ ] Type `-[x]` then a space → canonicalizes to `- [x] `.
- [ ] `-[]` with **no** following space → reads as a plain list line, **not** a checkbox (empty `[]` is not a checkbox).
- [ ] At content-start press **Backspace** → deletes the whole `- [ ] ` marker in one step.
- [ ] Press **Enter** on a checked `- [x] done` → continues as a fresh **unchecked** `- [ ] ` (not a duplicated `[x]`).

## E. List Nesting (Tab)

- [ ] On `- item` press **Tab** → one tab inserted at line start; the bullet + text indent one level together.
- [ ] Indent with **2 spaces** → counts as one nesting level (4 spaces = level 2).
- [ ] Indent to level 3, press **Tab** again → no further indent (capped at 3).
- [ ] Press **Tab** on a non-list line → default tab behaviour (no list nesting).
- [ ] ⟐ Across bullet / ordered / checkbox at the **same** nesting level → their text columns line up (post-fix alignment must hold — verify with screenshots).

## F. Headings

- [ ] Type `# Title` … through `###### Title` → each renders at its level's size; the `#` markers hide caret-out and grow/shrink with the level.
- [ ] Click into a heading (caret-in) → the `#` markers reveal (muted, non-bold) for editing.
- [ ] Type `#Title` (no space) → **not** a heading (stays literal).
- [ ] Type `####### Title` (7 hashes) → **not** a heading.
- [ ] `   # Title` (≤3 leading spaces) → still a heading; `    # Title` (4 spaces) → not.

## G. Blockquotes

- [ ] Type `> quote` → a card: left bar + tinted fill, `>` hidden, corners rounded (a lone line is both first and last).
- [ ] Type `> a` / Enter / `b` (two quote lines) → one continuous card; only the outer corners round.
- [ ] Type `>> deep` → nested quote; Enter continues with `>> `.
- [ ] On a `> ` line press **Enter** → continues `> `; **Shift+Enter** exits.
- [ ] Type `>a` (no space) or a bare `>` → **not** a blockquote (no card).
- [ ] Caret inside a quote line → the `>` stays hidden (the card is always-on, not caret-aware) but the text is editable.

## H. Horizontal Rule

- [ ] Type `---` on its own line, caret-out → a full-width hairline.
- [ ] `***` and `___` → same hairline.
- [ ] Click onto the `---` line (caret-in) → the literal `---` reveals for editing.
- [ ] `--` (two dashes) → **not** an HR.

## I. Fenced Code Blocks

- [ ] Type a block: ```` ```js ```` / Enter / `code` / Enter / ```` ``` ````. Caret outside → all block lines get the code background + monospace; first/last corners round; the ` ```js `/` ``` ` fence lines are hidden.
- [ ] Click **inside** the block → both fence lines reveal (editable).
- [ ] An unclosed ```` ``` ```` → the block runs to the end of the document.

## J. Links, Wikilinks, Images

- [ ] Type `[[Page]]`, caret-out → "Page" styled as a connection (coloured inline text); `[[` `]]` hidden.
- [ ] Caret at the **end** of `[[Page]]` (just past `]]`) → the link is **not** active (closing `]]` already passed).
- [ ] Type `[text](http://u)`, caret-out → "text" as a link.
- [ ] Type `![[pic]]` → image embed; it wins over wikilink (no connection styling on "pic").
- [ ] ⟐ Type `[` then `[` → yields `[[]]` with the caret between, **one** trailing `]]` (post-fix: no stray `[[]]]`).
- [ ] Inside `[[ | ]]` press **Enter** → caret jumps past **both** closers (`]]`), no newline.
- [ ] Inside a single `[ | ]` press **Enter** → caret jumps past the one closer.

## K. Auto-Pair / Auto-Delete

- [ ] Type `*` then `*` → `**|**` (caret between the bold pairs).
- [ ] Type `_`/`` ` `` similarly → `__|__` / `` ``|`` ``.
- [ ] `[` at line start or after whitespace → pairs to `[]`. `[` right after a word char → does **not** pair.
- [ ] `-[` → the `[` does **not** pair (so checkbox shorthand flows).
- [ ] `(` and `{` → always pair to `()` / `{}`.
- [ ] **Backspace** inside an empty `[]` → deletes both halves.
- [ ] ⟐ **Backspace** inside an empty `{}` → deletes both halves (post-fix: the consolidated pair table makes `{` round-trip).

## L. Dash + Arrow Auto-Format

- [ ] Type `--` then a letter (e.g. `a`) → em-dash `—a`.
- [ ] Type `---` (third dash) → stays `---` (HR preserved, no em-dash).
- [ ] Type `-` then `>` → `→`. Type `<` then `-` → `←`. Type `<-` then `>` → `↔`.
- [ ] Type `a ` `-` ` ` (word, space, dash, space) → en-dash `a – `.
- [ ] Inside a `[[wikilink]]` the spaced-dash en-dash does **not** fire.

## M. Inline Math (heuristic)

- [ ] Type `$x+1$` → renders as inline math (mathy content).
- [ ] Type `$word here$` → stays literal (prose, not math).
- [ ] Type `$5$` → stays literal (currency-like, not math).

## N. Title Bar

- [ ] The page title shows above the body with a hairline divider below it.
- [ ] Edit the title, press **Enter** → commits a file rename; focus drops into the body.
- [ ] Edit the title, press **Escape** → reverts to the original, blurs.
- [ ] Edit the title, click away (**blur**) → commits the rename.
- [ ] Clear the title to empty + commit → reverts to the original (no empty rename).
- [ ] ⟐ Trigger a rename that **fails** (e.g. a name collision) → the on-screen title reverts to the original (post-fix: no stale draft left showing).
- [ ] Scroll the body down → the title translates up 1:1, clips off past the top zone; scroll back → it returns.

## O. Zoom

- [ ] (Deferred — slider built, not yet placed.) When wired: adjusting zoom scales the whole editor (body + markers) in em off the base font size.

---

**Regression watch (from the fixes):** typing a space after `1.`, editing inside any marker, caret entering the marker gutter, bold immediately after a marker, and cross-type nested-list alignment — these are the cases the marker rework specifically repairs. Give them extra scrutiny.
