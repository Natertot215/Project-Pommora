## Electron Hardening + Trim — Plan (V2)

> **Status: revised per adversarial review (V1 → V2); one confirming review pass from ratified.** Not yet ratified — see Execution discipline.

> **Honest reframe (the review's headline).** On **macOS** there is essentially no "heavy weight trim" available without leaving Electron. The locale strip saves ~**0.2–0.5 MB** (not the 6–10 MB V1 claimed — those are Windows figures), the disk-cache cap is largely ignored by Chromium, and Chromium itself is an un-trimmable floor. **The real value of this plan is security hardening** (closing the Node-surface attack vectors + killing the `ELECTRON_RUN_AS_NODE` foot-gun) — the size win is incidental. The genuine weight move is the system-WebView shell swap, deliberately **held for later**.

**Review fold (V1 → V2):** deferred two fuses that break/are-pointless on an ad-hoc build (`enableEmbeddedAsarIntegrityValidation`, `onlyLoadAppFromAsar`); added `resetAdHocDarwinSignature: true` (Apple-Silicon ad-hoc launch fix); dropped `enableCookieEncryption` (no value for a local `app://` app + one-way-corruption caveat); corrected the locale size; corrected the cache approach (`disk-cache-size` is ignored); strengthened the V8-snapshot defer to "crash footgun"; reframed the plan as hardening-first.

### What this does, in plain terms

The app is a small website running inside its own private copy of the Chrome browser engine. We **can't** make it meaningfully smaller — the browser is the floor, and on a Mac the only removable fat (unused language packs) is half a megabyte. What we *can* do is **lock the release build down**: flip on one-way "fuses" that permanently disable developer back-doors baked into Electron (running the app as a plain script, attaching a debugger, injecting startup flags), and remove a known foot-gun. So this isn't really about weight — it's **pre-ship security hardening**, with a rounding-error of size as a bonus.

### Current state (grounded)

- Packaging: `npm run package` = `electron-vite build && electron-builder && npm rebuild better-sqlite3` → `release/mac-arm64/Pommora.app`.
- `electron-builder.yml`: `mac.target: dir`, `identity: null` (ad-hoc), `npmRebuild: true`, `asarUnpack: ['**/*.node']`. No `electronLanguages`, no `electronFuses` today.
- Installed: app-builder-lib 26.15.3, @electron/fuses 1.8.0 (both support the keys below — confirmed in source).

### Phase 1 — Locale strip (metadata honesty, ~0.5 MB)

**Files:** `electron-builder.yml`.

- Add top-level `electronLanguages: ['en']`. electron-builder deletes every non-`en` `.lproj` from the framework Resources (confirmed: `app-builder-lib/out/electron/ElectronFramework.js`).
- **Honest size:** ~0.2–0.5 MB on macOS (each `locale.pak` is KB-scale). Worth it mainly so the app stops advertising 50 languages it can't speak — not for the bytes.
- **Verify:** `npm run package` succeeds; `du -sh release/mac-arm64/Pommora.app` before/after (record delta); Nathan relaunches → works.
- Green commit.

### Phase 2 — Hardening fuses (the real value)

**Files:** `electron-builder.yml`.

- electron-builder flips fuse bits **before signing** (`platformPackager.js:251`, literal comment: "the fuses MUST be flipped right before signing"), then ad-hoc-signs the result. Corrected fuse set (ad-hoc-safe):
  ```yaml
  electronFuses:
    runAsNode: false                          # packaged app can't run as plain Node
    enableNodeOptionsEnvironmentVariable: false
    enableNodeCliInspectArguments: false
    resetAdHocDarwinSignature: true           # REQUIRED: re-seal after fuse-flip or an Apple-Silicon ad-hoc build ships "damaged"/won't launch
  ```
- **Deferred until Developer ID signing exists (do NOT set on the ad-hoc build):** `enableEmbeddedAsarIntegrityValidation` + `onlyLoadAppFromAsar`. On an ad-hoc bundle there's no cert chain, so the integrity guarantee is trivially bypassable *and* you inherit a hard crash-on-hash-mismatch failure mode. They pay off only on a Developer-ID-signed + notarized bundle — gate them there.
- **Dropped:** `enableCookieEncryption` — a local-first app served over `app://` has no auth cookies to protect; the fuse is hardening theater here and carries a one-way-migration corruption caveat.
- **Why it's safe (verified):** fuses bake into the *packaged* Mach-O only; `node_modules/.bin/electron` is untouched, so the GUI dev launch and the `ELECTRON_RUN_AS_NODE=1 ./node_modules/.bin/electron -e "new (require('better-sqlite3'))(':memory:')"` ABI check both keep working.
- **Forward-looking caveat:** `runAsNode: false` also disables `child_process.fork` in the packaged main (it relies on that env var). `src/main/index.ts` doesn't fork today; if main ever needs a child process, use `utilityProcess`, not `fork`.
- **Verify (all must pass):** `npm run package` succeeds; packaged app launches (Nathan); dev GUI launch + the ABI-check command still work; `codesign --verify release/mac-arm64/Pommora.app` passes.
- Green commit.

### Phase 3 — Cache cap (OPTIONAL — near the noise floor)

**Files:** `src/main/index.ts`.

- `app.commandLine.appendSwitch('disk-cache-size', …)` is **widely reported ignored** (Chromium computes its own size). Don't rely on it. The renderer is already served over the `app://` protocol (`index.ts:43`), which bypasses the HTTP cache entirely — so there's little app cache to cap. If anything, call `session.defaultSession.clearCache()` on a schedule.
- **Priority: LOW — likely drop.** The win is tens of MB at best and the lever is unreliable. Measure idle RAM (Nathan, Activity Monitor); if negligible, skip this phase and note it.

### Phase 4 — V8 snapshot (DEFER — active crash footgun)

- The `loadBrowserProcessSpecificV8Snapshot` fuse trims first-paint context creation (~40 ms → <2 ms) but **does nothing for size/RAM**, and enabling it without shipping `browser_v8_context_snapshot.bin` **crashes the packaged app on launch** (electron-builder doesn't include the file — eb #8797). **Do not enable** without a fresh, deliberate decision and the snapshot build wired.

### Coverage note (for when Developer ID lands)

The thing that actually gates notarization isn't fuses — it's the **hardened runtime + the `com.apple.security.cs.allow-jit` entitlement** (Chromium needs JIT), per `Resources/Distribution.md`. When the build moves off ad-hoc, that entitlement + the two deferred integrity fuses land together as the real "release hardening" step.

### Verification (whole plan)

- Headless gate each phase: `npm run typecheck && npx vitest run && npm run build` clean, then `npm run package` succeeds.
- Size: `du -sh release/mac-arm64/Pommora.app` before/after (expect a rounding error — that's the honest result).
- The app can't be launched/seen from the agent shell — **Nathan is the visual verifier** for "it still works."

### Execution discipline

Follows the project review→revise loop + execution conventions (`Studio/.claude/rules/Review-Discipline.md` + Pommora `CLAUDE.md`):

- **Adversarial review before ratifying.** A compile-grounding + logic/coverage review runs via a dispatched **standard agent** (not Workflow). V1 ran one round (folded above → V2); a confirming round runs before ratify. Fold + re-version each round until one comes back clean. Status stays "revised, pending confirming review" — never "final" pre-clean-round.
- **One green commit per phase.** Never batch.
- **Re-assess between green commits.** Read the remaining phases against what shipped; rewrite stale assumptions. Only green commits are facts.
- **Verify yourself.** Confirm size/behavior against the real artifact (`du -sh`, the running app) — never on an agent's word.
- **Nathan is the GUI verifier.**
