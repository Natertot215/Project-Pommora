## Typography

Pommora's type system. **Source of truth: the Figma "Pommora - React" library** (text styles); this doc is its on-disk spec. Family is **Inter** (variable), letter-spacing **0** throughout. Every style carries two weights — **Standard** and **Emphasized**.

### The ramp (established in Figma)

| Style | Size / line | Standard | Emphasized | Role |
|---|---|---|---|---|
| Large Title | 26 / 32 | Regular 400 | Bold 700 | top-level titles |
| Title 1 | 22 / 26 | Regular | Bold | |
| Title 2 | 17 / 22 | Regular | Bold | |
| Title 3 | 15 / 20 | Regular | Bold | section headers |
| Headline | 14 / 18 | **Medium 500** | Bold 700 | emphasized heading, distinct from Body |
| Body | 13 / 16 | Regular | Bold | paragraph / default UI text |
| Callout | 12 / 15 | Regular | **Bold** | in-text quotes |
| Control | 12 / 15 | Regular | **Semibold 600** | chips, labels, UI controls |
| Caption | 11 / 14 | Regular | Semibold | secondary captions |
| Footnote | 10 / 13 | Regular | Semibold | smallest text |

Derived from the macOS AppKit text scale (drawn in Inter), with deliberate edits: Headline bumped to 14 / Medium so it reads distinctly from Body; **Callout** repurposed for in-text quotes (Bold emphasis) and **Control** added for chips/labels (Semibold emphasis); Caption 1 + 2 merged into one **Caption**; Subheadline dropped. Standard weight is **Regular** for every style except Headline (**Medium**).

### Weights

Four Inter weights: **Regular 400** (all Standard except Headline) · **Medium 500** (Headline Standard) · **Semibold 600** (Emphasized of Callout-range → Footnote) · **Bold 700** (Emphasized of Large Title → Body, plus Callout). Emphasis is **role-driven**, not a blanket size rule.

### Where each style goes

- **Sidebar items** → Body (13).
- **Menu / dropdown items** → Control (12); active row → Control Emphasized.
- **Chips** → Control / Emphasized (12 Semibold).
- **Headings** → Title 3 / Title 2 / … / Large Title by level; **Headline** for an emphasized heading at body scale.
- **Page body** → Body; **quotes** → Callout.

(Grounded in the Swift app's usage: sidebar 14, `Typography.row = .callout` (12), `chip = .callout.semibold`.)

### Label colors

Text color is separate from the type ramp. Three label tones on one base `#F1F1F1`: **primary** 100% · **secondary** 65% · **tertiary** 35%. Catalogued in `Design.md` → Colors.

### In code — planned

Not yet authored. Plan: `design/tokens/typography.css.ts` (vanilla-extract) exposing each style as `{family, size, lineHeight}` + its two weights, referenced as `vars.font.<style>`. Inter is already loaded (`@fontsource-variable/inter`, family `Inter Variable`) and set as the app font — see `Design.md` → Tooling.

### Not yet established — stubs

- **Letter-spacing scale** — `0` everywhere today; revisit if tighter display tracking is wanted.
- **Monospace / code font** — code blocks + inline code in the Markdown editor (font choice + a `mono` style).
- **Markdown element mapping** — which ramp style renders each Markdown element (headings, body, blockquote, code, caption).
- **Tabular / monospaced digits** — tables + numeric columns.
- **Truncation + line-clamp** conventions.
- **Dynamic Type / responsive sizing** — fixed px for now.
