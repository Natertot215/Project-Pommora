## Typography

Pommora's type system. Source of truth: the Figma "Pommora - React" library (text styles); this doc is its on-disk spec. Family is **Inter** (variable, weight axis 100–900), letter-spacing **0** throughout. Every style carries two variants — **Standard** and **Emphasized** — each bound to one of four named weights. The literal sizes and line heights live in the token file.

> **Two layers, shared words.** *Standard* and *Emphasized* name both a style's two **variants** (`text.body.standard` / `.emphasized`) and two of the four **weights** (Standard 400 / Emphasized 500). They're independent: a variant resolves to whatever weight its role needs — e.g. Headline's *Standard variant* uses the *Emphasized (500) weight*.

### The ramp

Columns are the two **variants**; cells are the **weight** each resolves to.

| Style       | Standard        | Emphasized       | Role                                    |
| ----------- | --------------- | ---------------- | --------------------------------------- |
| Large Title | Standard        | Bold             | top-level titles                        |
| Title 1     | Standard        | Bold             |                                         |
| Title 2     | Standard        | Bold             |                                         |
| Title 3     | Standard        | Bold             | section headers                         |
| Headline    | **Emphasized**  | **Semibold**     | menu section headers; body-size heading |
| Body        | Standard        | Bold             | paragraph / default UI text             |
| Callout     | Standard        | **Bold**         | in-text quotes                          |
| Control     | Standard        | **Semibold**     | chips, labels, UI controls              |
| Caption     | Standard        | Semibold         | secondary captions                      |
| Footnote    | Standard        | Semibold         | smallest text                           |

Derived from the macOS AppKit text scale drawn in Inter, with deliberate edits: **Headline** sits at body size with Emphasized / Semibold weights — distinct from Body by weight, used for menu section headers; **Callout** carries in-text quotes and menu item titles (Bold emphasis); **Control** drives chips / labels / buttons (Semibold emphasis). The Standard variant is the **Standard (400)** weight everywhere except Headline, which takes **Emphasized (500)**.

### Weights

Four Inter weights on a ladder — **Standard 400 · Emphasized 500 · Semibold 600 · Bold 700** — defined once in the token file (editable in place; the variable font renders any value). By role: **Standard** backs every Standard variant except Headline · **Emphasized** is Headline's Standard variant · **Semibold** is Headline's Emphasized plus Control / Caption / Footnote Emphasized · **Bold** is the Emphasized of Large Title → Body, plus Callout. Emphasis is **role-driven**, not a blanket size rule.

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

The type tokens are authored in vanilla-extract in two layers: **font primitives** (family, the four weights, and a size/line scale per style) as the single source, and **composed text classes** (`text.<style>.{standard, emphasized}`) that apply a whole style to a component. The weights are also bridged to `--weight-{standard,emphasized,semibold,bold}` CSS vars so plain CSS draws from the same numbers. Inter loads as a variable font; the build extracts the CSS.

### Not yet established — stubs

- **Letter-spacing scale** — `0` everywhere today; revisit if tighter display tracking is wanted.
- **Monospace / code font** — code blocks + inline code in the Markdown editor (font choice + a `mono` style).
- **Markdown element mapping** — which ramp style renders each Markdown element (headings, body, blockquote, code, caption).
- **Tabular / monospaced digits** — tables + numeric columns.
- **Truncation + line-clamp** conventions.
- **Dynamic Type / responsive sizing** — fixed px for now.
