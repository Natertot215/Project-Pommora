### Guidelines

Behavioral rules and constraints grouped by domain. Add new entries to prevent mistakes from repeating.

#### Active

- `UIX-Guide.md` — SwiftUI + AppKit design philosophy, component conventions, AppKit interop guidance.
- `CRUD-Patterns.md` — SwiftUI patterns for per-entity CRUD UI, atomic-write discipline, manager pattern.
- `Paradigm-Decisions.md` — Confirmation protocol for paradigm-solidifying code (on-disk schemas, wire encodings, defaults that lock once data exists) + registry of confirmed decisions.

#### Domains

Create files for each domain as needed:
- `Code.md` — code style, patterns, conventions
- `Testing.md` — testing requirements and practices
- `Git.md` — branching strategy, commit standards
- `Performance.md` — performance constraints
- [Other domains as needed]

Each file should list specific rules with examples when helpful.

> Note: `Symbols-guide.md` (semantic-role icon indirection) is React-specific and lives at `// ReactInfo//Symbols-guide.md` — SwiftUI uses SF Symbols natively with no indirection layer needed.
