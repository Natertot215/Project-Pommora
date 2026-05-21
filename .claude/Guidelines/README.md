### Guidelines

Behavioral rules and constraints grouped by domain. Add new entries to prevent mistakes from repeating.

#### Active

- `Design.md` — SwiftUI + AppKit design philosophy, brand-value placement, component conventions, AppKit interop guidance.
- `Symbols.md` — SF Symbol registry. Application ↔ Symbol table; the canonical source for what symbol goes where in the app. Spec for the future in-app Symbol Settings surface.
- `Markdown.md` — Rules-of-engagement for the page editor (swift-markdown, swift-markdown-engine vendored, TextKit 2, Pommora's customizations). Anti-patterns, dynamic-syntax pattern, state mutation rules, Nathan-locked clarifications, file:line reference index. Read this before touching any markdown editor code.
- `CRUD-Patterns.md` — SwiftUI patterns for per-entity CRUD UI, atomic-write discipline, manager pattern, PreviewWindow prerequisite.
- `Paradigm-Decisions.md` — Confirmation protocol for paradigm-solidifying code (on-disk schemas, wire encodings, defaults that lock once data exists) + registry of confirmed decisions.

#### Domains

Create files for each domain as needed:
- `Code.md` — code style, patterns, conventions
- `Testing.md` — testing requirements and practices
- `Git.md` — branching strategy, commit standards
- `Performance.md` — performance constraints
- [Other domains as needed]

Each file should list specific rules with examples when helpful.

> Note: `// ReactInfo//Symbols-guide.md` is the React-side icon-role-indirection counterpart; SwiftUI uses SF Symbols natively with no indirection layer needed — the registry pattern in `Symbols.md` above is Pommora's Swift-side equivalent.
