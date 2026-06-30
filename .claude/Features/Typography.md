## Typography

Pommora's type system. Source of truth for **sizes**: the Figma "Pommora - React" library (text styles); this doc is its on-disk spec. Family is **Inter** (variable, weight axis 100–900), letter-spacing **0** throughout. Every style exposes all four weights by name — **Standard 400 · Emphasized 500 · Semibold 600 · Bold 700** — so a variant *is* its weight. The literal sizes and line heights live in the token file.

> **Variant = weight.** A style's variants map straight to the weight ladder: `text.body.standard` is 400, `.emphasized` 500, `.semibold` 600, `.bold` 700 — the same for every style. Pick the size by style key, the weight by variant name; there's no role-based remapping.

### The Ramp

Every style exposes the same four weights by name (**Standard 400 · Emphasized 500 · Semibold 600 · Bold 700**); the only thing that varies per style is **size + line height** (in the token file). `text.<style>.<weight>` composes the two — size from the style, weight from the variant.

| Style       | Role                                      |
| ----------- | ----------------------------------------- |
| Large Title | top-level titles                          |
| Title 1–3   | section headers by level                  |
| Headline    | body-size heading; menu section headers   |
| Body        | paragraph / default UI text               |
| Callout     | in-text quotes; menu item titles          |
| Control     | chips, labels, UI controls                |
| Caption     | secondary captions                        |
| Footnote    | small text / detail                       |
| Subline     | Subfield + Mini Items — the smallest text |

Sizes derive from the macOS AppKit text scale drawn in Inter, with deliberate edits: **Headline** sits at body size (distinct only by the weight you choose); **Callout** carries in-text quotes and menu item titles; **Control** drives chips / labels / buttons.

### Weights

Four Inter weights on a ladder — **Standard 400 · Emphasized 500 · Semibold 600 · Bold 700** — defined once in the token file (editable in place; the variable font renders any value). Every style exposes all four by name, and the variant name is the weight it renders: `.emphasized` is 500 everywhere, `.bold` is 700 everywhere. Bridged to `--weight-{standard,emphasized,semibold,bold}` CSS vars so plain CSS draws the same numbers.

### Where Each Style Goes

- **Sidebar items** → Body.
- **Menu / dropdown item titles** → Callout / Standard.
- **Menu Headings** → Headline / Standard.
- **Labels** → Control / Emphasized.
- **Buttons** → Control / Emphasized.
- **Chips** → Control / Semibold.
- **Sub-label** → Caption / Standard.
- **Detail** → Footnote / Emphasized.
- **Subfield (footer)** → Subline / Emphasized — the smallest text in the app.
- **Headings** → Title 3 / Title 2 / … / Large Title by level.
- **Page body** → Body; **quotes** → Callout.

(Every component title / label / content text is bound to a **live Figma text style** — editing the style propagates to all variants and gallery instances.)

### Label Colors

Text color is separate from the type ramp. Three label tones on one near-white base at descending opacities — **primary · secondary · tertiary**. Catalogued in `Design.md` → Color.

### In Code

The type tokens are authored in vanilla-extract in two layers: **font primitives** (family, the four weights, and a size/line scale per style) as the single source, and **composed text classes** (`text.<style>.{standard, emphasized, semibold, bold}`) that apply a whole style to a component. The weights are also bridged to `--weight-{standard,emphasized,semibold,bold}` CSS vars so plain CSS draws from the same numbers. Inter loads as a variable font; the build extracts the CSS.

### Not Yet Established — Stubs

- **Letter-spacing scale** — `0` everywhere today; revisit if tighter display tracking is wanted.
- **Monospace / code font** — code blocks + inline code in the Markdown editor (font choice + a `mono` style).
- **Markdown element mapping** — which ramp style renders each Markdown element (headings, body, blockquote, code, caption).
- **Tabular / monospaced digits** — tables + numeric columns.
- **Truncation + line-clamp** conventions.
- **Dynamic Type / responsive sizing** — fixed px for now.
