# Page Previews — Post-Compact Execution Prompt

Paste-ready (or auto-resume) instructions for the executing context. Both governing documents live beside this file and are CERTIFIED law:

1. `.claude/Planning/Page Previews — Decision Log.md` — the spec. Read its **Status**, **Shipped Shell**, **Planning Requirements**, and **Core** sections first; on any ambiguity the log wins.
2. `.claude/Planning/Page Previews — Implementation Plan.md` — the plan. Execute it **inline, phase by phase, in order**, checking off steps.

## Standing Orders (Nathan's, non-negotiable)

- **Phase Protocol every phase:** gates green (`set -o pipefail; npm run typecheck && npx vitest run && npm run build`, background, read the summary lines) → `build-breaking-agent` on the phase diff (verify each finding at its citation yourself before folding) → `code-simplifier` + `comment-killer-agent` → re-gate if they touched code → commit explicit paths, push → **ping Nathan's phone** (PushNotification) → re-read the plan and rewrite drifted downstream tasks before the next phase.
- **Confirm every design choice inline as you make it** (a one-line disclosure in the running response), AND restate all of them in the final report.
- **The final report is Phase 9's Task 9.2, at the very end, nowhere else** — every knob (name · file · default), every design decision with its id, every assumption taken/deferred, what Nathan must eyeball live.
- Standard Agent dispatches only — never the Workflow tool. Don't stop until the plan is finished; Nathan may interject with live UIX tweaks — fold them immediately (they're law), batch-commit, keep going.
- Doc reconciliation (Phase 9.1) lands WITH code, committed. Write docs as durable truth, never correction-framed.

## Environment Facts

- Dev app: `env -u ELECTRON_RUN_AS_NODE npm run dev` (never launch with the env var set). Main/preload changes need a dev-process restart; CM6 extension changes need a full renderer reload; CSS HMRs.
- Visual verification: CDP screenshot → **Read the PNG** (that's what reaches Nathan's phone) — never SendUserFile. Zero-mutation recipes + capture-restore for live-app driving are in project memory (`project-react-headless-screenshot-via-cdp`).
- Biome hook formats every write (single-quote, no semicolons) — an Edit failing on whitespace means re-read and retry. `npm run typecheck` is the only type gate.
- Tests run against `TEST_NEXUS_PATH`; the running app uses the real Nexus — never mutate it without capture-restore.
- Nathan's pending confirms (flagged [assumed] in the log — surface in the final report, don't block on them): I-25 nav-row in-renderer carve-out, H-9 banner'd morph variant, H-2 map-tab content model, H-10 no-auto-summon, B-6 SettingsPane row shape, B-7 placeholder dismiss, G-2 Figma pass.

## Current State Pointer

The shell + guards are shipped through the commits listed in the log's Shipped Shell section; the spec survived three adversarial rounds and the plan its own review cycle (see git log for the certification commits). Execution begins at the first unchecked task in the plan — Phase 1, Task 1.1 unless boxes are already ticked.
