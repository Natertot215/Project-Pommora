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

- **2026-04-28** — Orphan-row overflow branch (`SidebarView.orphanRow`, lines 207–231 pre-fix). When `orphanFiles.count > 25`, a separate `ScrollView + LazyVStack` path was rendered with hand-rolled selection: `RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.85))` background, `.padding(.horizontal, 8).padding(.vertical, 4)`, `Color.white` foreground, and `onTapGesture` bypassing `List`'s `.tag` selection. A hardcoded `CGFloat = 26` estimated row height was used for the capped `ScrollView` height. This was a scrapped-feature artifact that was never cleaned up. The fix: delete the overflow branch entirely and render all orphan files in the normal `ForEach` path — `List` itself scrolls and handles selection correctly.

- **2026-04-28** — Search silently excluded orphan files (`LibrarySearch.run` only iterated `folder.files`). Orphan files (`folder == nil`) are first-class library content and must be included in search. The fix: extend `run(query:folders:orphanFiles:cache:)` to also iterate orphans. Lesson: any time there are two code paths for files (folder-resident vs orphan), both paths must receive identical treatment unless there is an explicit, documented reason to differ.
