# Lesson: Don't hand-tune UI dimensions — use SwiftUI semantic primitives

**Read this before:** any UI change in Pommora — sizing, spacing, fonts, icon scale, row heights, padding, color choices, drag/drop, animations. Anything visible.

## The mistake

Reaching for hand-coded dimensions instead of SwiftUI's semantic modifiers. Concrete examples I have actually shipped that Nathan correctly flagged:

- `.frame(width: 22, alignment: .center)` on an `Image` to "make the icon bigger"
- `.font(.system(size: 13))` to size a label
- `.font(.title3)` applied to an icon (instead of letting `Label` + `.imageScale` handle it)
- Hand-rolled `HStack { Image; Text }` instead of `Label`
- Manual row paddings to fake `.controlSize(.regular)` behavior
- Nested `ScrollView` hacks instead of `.listSectionSeparator(.hidden)`
- Manual width math on title vs. detail instead of `.layoutPriority` + `.lineLimit().truncationMode(.tail)`

## Why it's wrong

Apple's semantic modifiers automatically scale across:

- `.controlSize(.small/.regular/.large)`
- The system **Sidebar size** setting (System Settings → Appearance)
- **Dynamic Type** (accessibility text size)

Hand-tuned literals silently break all three. The app looks fine on my machine and wrong on every other machine. Nathan's framing: *"making up what I don't know about design principles."*

## The rule

| Want this | Use this | Don't do this |
|---|---|---|
| Bigger icon in a row | `.imageScale(.large)` on the `Label`/`List` | `.frame(width: 22)` on `Image` |
| Bigger icon + text together | `Label` + `.font(.headline)` + `.imageScale(.large)` | `.font(.system(size: 16))` |
| Sidebar size variants | `.controlSize(.small/.regular/.large)` (per HIG Sidebars) | hand-tuned row paddings |
| Hide section dividers in a `List` | `.listSectionSeparator(.hidden)` | nested `ScrollView` hacks |
| Detail wins over title in a row | `.layoutPriority(1)` on detail + `.lineLimit(1).truncationMode(.tail)` on title | manual width math |
| Color | `Color.accentColor`, `.primary`, `.secondary`, `Color(nsColor: .systemX)` | hex literals from Figma |
| Material backgrounds | `.regularMaterial`, `.thinMaterial`, etc. | hand-mixed RGBA |

## Verification protocol (before writing the code)

1. Identify the exact SwiftUI primitive you'll use. Name it out loud.
2. Confirm it exists and behaves as you think — see [swiftui-api-verification.md](swiftui-api-verification.md).
3. If matching a screenshot Nathan sent from Finder/Mail/Notes/Photos/Settings/Xcode, name the primitive that produces that look. The screenshot is source of truth; your job is to map it to the primitive.
4. If Apple's HIG doesn't specify exact dimensions for what you're building, **say so explicitly** to Nathan and ask. Don't pick a number.

## Incidents

- **2026-04-26** — Initial occurrence. Sidebar work introduced `.frame(width: 22)` on icons and `.font(.title3)` on a Label-replacement HStack. Nathan flagged it; rewrote with `Label` + `.imageScale(.large)` + `.controlSize(.regular)`. Source captured to project memory; promoted into CLAUDE.md and this file on 2026-04-27.
