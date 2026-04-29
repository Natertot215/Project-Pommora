# Lessons

One file per failure pattern. The point is to **never make the same mistake twice**. CLAUDE.md points here and tells you which file is required reading before which kind of work.

Rules for this directory:

- **One mistake per file.** No catch-all docs.
- **Be specific.** Cite the actual line of code or modifier name that went wrong, not a vague principle.
- **State the trigger.** Every file opens with "Read this before:" so future-you knows when it applies.
- **Append, don't rewrite.** When the same pattern recurs, add a new dated incident under "## Incidents" rather than reflowing the doc.
- **Keep it short.** If a lesson is longer than ~80 lines, it's two lessons.

## Index

- [ui-dimensions-and-semantic-primitives.md](ui-dimensions-and-semantic-primitives.md) — Don't hand-tune `.frame`, `.font(.system(size:))`, paddings, row heights. Use SwiftUI semantic primitives + cite Apple HIG / shipped apps.
- [swiftui-api-verification.md](swiftui-api-verification.md) — Don't invent SwiftUI signatures from memory. Grep the `.swiftinterface` (or read Apple docs) before introducing any modifier or initializer.
- [navigation-split-view-columns.md](navigation-split-view-columns.md) — Use `.navigationSplitViewStyle(.prominentDetail)` so sidebar and content columns resize independently against the detail pane.
