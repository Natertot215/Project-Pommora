## Typography

Pommora's type system. **Source of truth: the Figma "Pommora - React" library** (text styles); this doc is its on-disk spec. Family is **Inter** (variable), letter-spacing **0** throughout. Every style carries two weights — **Standard** and **Emphasized**.

### The ramp (established in Figma)

| Style | Size / line | Standard | Emphasized | Role |
|---|---|---|---|---|
| Large Title | 26 / 32 | Regular 400 | Bold 700 | top-level titles |
| Title 1 | 22 / 26 | Regular | Bold | |
| Title 2 | 17 / 22 | Regular | Bold | |
| Title 3 | 15 / 20 | Regular | Bold | section headers |
| Headline | 13 / 16 | **Medium 500** | **Semibold 600** | menu section headers; body-size heading |
| Body | 13 / 16 | Regular | Bold | paragraph / default UI text |
| Callout | 12 / 15 | Regular | **Bold** | in-text quotes |
| Control | 12 / 15 | Regular | **Semibold 600** | chips, labels, UI controls |
| Caption | 11 / 14 | Regular | Semibold | secondary captions |
| Footnote | 10 / 13 | Regular | Semibold | smallest text |

Derived from the macOS AppKit text scale (drawn in Inter), with deliberate edits: **Headline** sits at body size (13) with Medium / Semibold weights — distinct from Body by weight, used for menu section headers; **Callout** repurposed for in-text quotes and menu item titles (Bold emphasis) and **Control** added for chips / labels / buttons (Semibold emphasis); Caption 1 + 2 merged into one **Caption**; Subheadline dropped. Standard weight is **Regular** for every style except Headline (**Medium**).

### Weights

Four Inter weights: **Regular 400** (all Standard except Headline) · **Medium 500** (Headline Standard) · **Semibold 600** (Headline Emphasized + Control / Caption / Footnote Emphasized) · **Bold 700** (Emphasized of Large Title → Body, plus Callout). Emphasis is **role-driven**, not a blanket size rule.

### Where each style goes

- **Sidebar items** → Body (13).
- **Menu / dropdown item titles** → Callout / Standard (12) — every state (no weight change on hover / selected).
- **Menu section headers** (Menu Heading) → Headline (13 / Semibold).
- **Labels** → Control / Emphasized (12 Semibold).
- **Buttons** → Control / Emphasized (12 Semibold).
- **Chips** → Control / Emphasized (12 Semibold).
- **Sub-label** → Caption / Standard (11); **Detail** → Footnote / Emphasized (10).
- **Headings** → Title 3 / Title 2 / … / Large Title by level.
- **Page body** → Body; **quotes** → Callout.

(Every component title / label / content text is bound to a **live Figma text style** — editing the style propagates to all variants and gallery instances. SF Pro icon glyphs keep their font; only their size is set.)

### Label colors

Text color is separate from the type ramp. Three label tones on one base `#F1F1F1`: **primary** 100% · **secondary** 65% · **tertiary** 35%. Catalogued in `Design.md` → Colors.

### In code — authored

`design/tokens/typography.css.ts` (vanilla-extract), two layers:
- **`font` primitives** (`createGlobalTheme`) — `font.family`, `font.weight.{regular, medium, semibold, bold}` (400 / 500 / 600 / 700), and `font.scale.<style>.{size, line}` for all ten styles. The single source — edit a value and it propagates.
- **`text` composed classes** — `text.<style>.{standard, emphasized}` apply a whole style: `className={text.headline.emphasized}`.

Unified in `index.ts` (`import { vars, text } from '@renderer/design/tokens'`; primitives read as `vars.font.*`). Inter loads via `@fontsource-variable/inter` (family `Inter Variable`). The build extracts the CSS green.

### Not yet established — stubs

- **Letter-spacing scale** — `0` everywhere today; revisit if tighter display tracking is wanted.
- **Monospace / code font** — code blocks + inline code in the Markdown editor (font choice + a `mono` style).
- **Markdown element mapping** — which ramp style renders each Markdown element (headings, body, blockquote, code, caption).
- **Tabular / monospaced digits** — tables + numeric columns.
- **Truncation + line-clamp** conventions.
- **Dynamic Type / responsive sizing** — fixed px for now.
