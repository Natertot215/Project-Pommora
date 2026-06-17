## Typography

Pommora's type system. Source of truth: the Figma "Pommora - React" library (text styles); this doc is its on-disk spec. Family is **Inter** (variable), letter-spacing **0** throughout. Every style carries two weights — **Standard** and **Emphasized**. The literal sizes and line heights live in the token file.

### The ramp

| Style       | Standard       | Emphasized       | Role                                    |
| ----------- | -------------- | ---------------- | --------------------------------------- |
| Large Title | Regular        | Bold             | top-level titles                        |
| Title 1     | Regular        | Bold             |                                         |
| Title 2     | Regular        | Bold             |                                         |
| Title 3     | Regular        | Bold             | section headers                         |
| Headline    | **Medium**     | **Semibold**     | menu section headers; body-size heading |
| Body        | Regular        | Bold             | paragraph / default UI text             |
| Callout     | Regular        | **Bold**         | in-text quotes                          |
| Control     | Regular        | **Semibold**     | chips, labels, UI controls              |
| Caption     | Regular        | Semibold         | secondary captions                      |
| Footnote    | Regular        | Semibold         | smallest text                           |

Derived from the macOS AppKit text scale drawn in Inter, with deliberate edits: **Headline** sits at body size with Medium / Semibold weights — distinct from Body by weight, used for menu section headers; **Callout** carries in-text quotes and menu item titles (Bold emphasis); **Control** drives chips / labels / buttons (Semibold emphasis). Standard weight is **Regular** for every style except Headline (**Medium**).

### Weights

Four Inter weights: **Regular** (all Standard except Headline) · **Medium** (Headline Standard) · **Semibold** (Headline Emphasized + Control / Caption / Footnote Emphasized) · **Bold** (Emphasized of Large Title → Body, plus Callout). Emphasis is **role-driven**, not a blanket size rule.

### Where each style goes

- **Sidebar items** → Body.
- **Menu / dropdown item titles** → Callout / Standard.
- **Menu Headings** → Headline / Standard.
- **Labels** → Control / Emphasized.
- **Buttons** → Control / Emphasized.
- **Chips** → Control / Emphasized.
- **Sub-label** → Caption / Standard.
- **Detail** → Footnote / Emphasized.
- **Headings** → Title 3 / Title 2 / … / Large Title by level.
- **Page body** → Body; **quotes** → Callout.

(Every component title / label / content text is bound to a **live Figma text style** — editing the style propagates to all variants and gallery instances.)

### Label colors

Text color is separate from the type ramp. Three label tones on one near-white base at descending opacities — **primary · secondary · tertiary**. Catalogued in `Design.md` → Color.

### In code

The type tokens are authored in vanilla-extract in two layers: **font primitives** (family, the four weights, and a size/line scale per style) as the single source, and **composed text classes** (`text.<style>.{standard, emphasized}`) that apply a whole style to a component. Inter loads as a variable font; the build extracts the CSS.

### Not yet established — stubs

- **Letter-spacing scale** — `0` everywhere today; revisit if tighter display tracking is wanted.
- **Monospace / code font** — code blocks + inline code in the Markdown editor (font choice + a `mono` style).
- **Markdown element mapping** — which ramp style renders each Markdown element (headings, body, blockquote, code, caption).
- **Tabular / monospaced digits** — tables + numeric columns.
- **Truncation + line-clamp** conventions.
- **Dynamic Type / responsive sizing** — fixed px for now.
