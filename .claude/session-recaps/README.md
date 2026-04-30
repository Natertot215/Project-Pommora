# Session Recaps

Dated summaries of significant work sessions. One file per session.

## Filename format

`Session DD-MM-YY (#).md`

- `DD-MM-YY` — date the session ran (or ended, if it spanned days).
- `(#)` — disambiguator if multiple sessions occurred on the same day. Start at `(1)`.
- Example: `Session 30-04-26 (1).md`

## When to create one

**Only on Nathan's direction.** Recaps are not auto-generated at session end. Nathan asks for one when a session has produced something worth a permanent record — typically: completed feature, multi-iteration bug fix, architectural decision, scrapped attempt with surfaced constraints.

## What goes in a recap

- **Session date + title** — what the session was about.
- **Stable base** — commit hash the session started from.
- **What changed** — bulleted list of fixes / features / decisions, each tied to a file or symbol when possible.
- **Architectural constraints surfaced** — anything blocked or deferred.
- **Operational notes** — non-obvious environment state worth preserving (e.g. DerivedData hash, simulator selection, package versions).
- **Outstanding** — anything left unfinished, with enough context for the next session to pick it up.

Keep recaps concise. They are a historical record, not a tutorial.
