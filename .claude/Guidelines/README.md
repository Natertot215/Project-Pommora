### Guidelines

Behavioral rules and constraints grouped by domain. Add new entries to prevent mistakes from repeating.

#### Active

- `Design.md` — SwiftUI + AppKit design philosophy, brand-value placement, component conventions, AppKit interop guidance.
- `Symbols.md` — SF Symbol registry. Application ↔ Symbol table; the canonical source for what symbol goes where in the app. Spec for the future in-app Symbol Settings surface.
- `CRUD-Patterns.md` — SwiftUI patterns for per-entity CRUD UI, atomic-write discipline, manager pattern, PreviewWindow prerequisite.
- `Paradigm-Decisions.md` — Confirmation protocol for paradigm-solidifying code (on-disk schemas, wire encodings, defaults that lock once data exists) + registry of confirmed decisions.

#### Moved to `// rules//`

The page-editor rulebook (`MarkdownPM.md`, `paths:`-scoped to MarkdownPM files) and `Review-Discipline.md` (always-on) now live in `.claude/rules/`, which Claude Code auto-loads — so they apply automatically instead of only on manual reference.

> Note: `// ReactInfo//Symbols-guide.md` is the React-side icon-role-indirection counterpart; SwiftUI uses SF Symbols natively with no indirection layer needed — the registry pattern in `Symbols.md` above is Pommora's Swift-side equivalent.
