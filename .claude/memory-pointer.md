# Session Memory — Read Before Starting

Full memory is NOT injected here — large SessionStart output gets truncated to a short preview, so this hook only points. These files are on disk; read the relevant ones in full now:

- `.claude/Handoff.md` — current build state + near-term priorities (React/Electron — the active build)
- `.claude/Swift/Handoff.md` — the paused Swift build's handoff (archived under `.claude/Swift/`)
- `.remember/now.md` — current session buffer (plugin journal, most recent activity)
- `.remember/recent.md` — last ~7 days, compressed

Read the active build's Handoff + `.remember/now.md` at minimum. `.remember/recent.md` and `.remember/archive.md` are available for deeper history.
