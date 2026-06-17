## Native Companion Helper — Plan (V2: standalone helper)

> **Status: re-architected per adversarial review (V1 → V2); the new approach needs its own confirming review before ratifying.** Not ratified.

> **Why V1 was refuted (verified in source).** V1 embedded a QuickLook `.appex` inside the electron-builder `.app` and claimed electron-builder would sign it. **False, confirmed:** `macPackager.signApp` (`node_modules/app-builder-lib/out/macPackager.js:434-440`) signs only `${productFilename}.app` and `.app` bundles under `app.asar.unpacked` — it **never recurses into `Contents/PlugIns/*.appex`**. An injected appex ships unsigned → killed by Gatekeeper/PlugInKit. Embedding an app-extension in an Electron app is also undocumented/unproven (osx-sign #141; Apple forum 763450 trailed off).

> **Corrected approach.** Ship the QuickLook extension in a **standalone Xcode-built helper app**, signed + notarized the normal Xcode way (inside-out, automatic) — the **proven** pattern (Glance, QLMarkdown, PreviewMarkdown all do exactly this). This also **decouples signing**: only the small helper needs Developer ID; the main Electron app can stay ad-hoc.

**Review fold (V1 → V2):** abandoned the embed-in-Electron approach for a standalone Xcode helper; decoupled Phase 0 (helper-only Developer ID, not the whole app); fixed the UTI declaration (`public.markdown` isn't a real system UTI); fixed the render approach (`AttributedString(markdown:)` does NOT produce visual styling); added the first-launch registration step; named the thumbnail extension as separate/deferred.

### What this does, in plain terms

Today, spacebar on a Pommora page in Finder shows nothing useful. We build a **tiny separate native Mac app** whose only job is to teach macOS how to draw a Pommora page — so spacebar gives a clean rendered preview, like a PDF. It reads the same `.md` file off disk; it doesn't talk to the running app. *What it makes better:* Pommora starts to feel like a real Mac citizen, and it's the smallest safe step of the "Swift helper beside the web app" pattern that later powers Spotlight. Two real-world costs to know: it needs a **paid Apple developer signature** (a system preview plug-in won't run without it), and it's a genuinely separate little Mac program we build in Xcode — not a few lines bolted onto the existing app.

### Phase 0 — Developer ID for the helper (decoupled)

**Files:** the helper Xcode project's signing config (NOT `electron-builder.yml`).

- Only the **helper** needs **Developer ID Application** signing + **notarization** (Xcode handles inside-out signing automatically). The main Electron `Pommora.app` can remain ad-hoc.
- **Real-world prerequisite (flag for Nathan):** an **Apple Developer Program membership + a Developer ID certificate** — an account/cost step. A system QuickLook extension will not load ad-hoc or un-notarized.
- ~0.5 session once the certificate exists (just the helper's signing/notarize pipeline).

### Phase 1 — Standalone QuickLook helper app

**Use the `swiftui-expert-skill` for all Swift code.**

**Files:** a new Xcode project, e.g. `React/native/PommoraQuickLook/` (a minimal host app + a Quick Look Preview Extension target).

- **API:** `QLPreviewingController` with `NSExtensionPointIdentifier = com.apple.quicklook.preview` + `QLSupportedContentTypes`. (`.qlgenerator` is dead — removed entirely in macOS 15 Sequoia — so this modern API is the only path.)
- **UTI (corrected):** there is **no Apple system UTI for `.md`**. Declare it yourself via `UTImportedTypeDeclarations` (`net.daringfireball.markdown`, conforming to `public.plain-text`) and list every common variant in `QLSupportedContentTypes` (`net.daringfireball.markdown`, `net.ia.markdown`, …). Note: with multiple markdown QL plug-ins installed, which one macOS picks is undefined.
- **Render (corrected — this is the real work):** `AttributedString(markdown:)` produces block *metadata*, not visual styling (headings/lists/code render flat) — it is NOT a near-free render. Two viable v1 paths, both requiring real styling work:
  - **(preferred) `QLPreviewReply(dataOfContentType:)` emitting HTML + CSS** — QuickLook renders the HTML itself (NOT a WKWebView), giving clean dark-theme control at low cost. The CSS expresses the design intent (names + treatments, per the docs-name-code-holds-exacts rule — no need to mirror token literals).
  - **(alt) Pommora's in-house `MarkdownPM`** (swift-markdown-derived, already in the Swift build) → styled `NSAttributedString` → return as RTF.
  - **Do NOT use a WKWebView** in the extension — the QL sandbox imposes a ~120 MB / 30 s budget, spawns a web process, and ignores the network entitlement.
- **Distribution + registration (the open mechanic — see below):** the signed+notarized helper is bundled inside `Pommora.app` (e.g. `Contents/Library/`) and **launched once headlessly on first run** to register the extension with PlugInKit; OR shipped as a separate user-installed app (fully proven, but a second install step).
- **Verify:** helper builds (`xcodebuild`, headless); the `.app` carries a valid Developer-ID signature + notarization ticket (`codesign --verify`, `spctl -a`); **Nathan** installs + spacebar-previews a `.md` in Finder → sees the rendered preview.
- **Post-functional UIX review** on the real Finder preview before closeout.
- ~1.5 sessions (after Phase 0).

### Phase 2 — CoreSpotlight indexing + continuation (GATED — held)

> **Blocked.** Do not start before `pommora://` deep links ship (held for later). Scoped so it isn't lost.

**Use the `swiftui-expert-skill`.** A nexus indexer submits `CSSearchableItem`s (title, body snippet, `contentURL = pommora://nexus/<id>/page/<relPath>`); a Spotlight hit opens the app via the deep link. Hard prerequisite: the `pommora://` scheme + a renderer route handler. ~2 sessions once unblocked.

### Open items — must resolve in the confirming review / a spike

1. **Bundle-vs-separate-install + first-launch registration.** Does a Developer-ID-signed+notarized helper bundled *inside an ad-hoc `Pommora.app`* register and run cleanly on first launch, or does the ad-hoc outer wrapper trip Gatekeeper? The precedents (Glance/QLMarkdown) are *separately installed* apps — they don't cover the bundled-inside-an-ad-hoc-app case. **This needs a small spike before Phase 1 is ratified.**
2. **Thumbnail extension** (Finder file-icon thumbnail) is a *separate* `QLThumbnailProvider` extension, not covered by the preview extension. Deferred; named here so "feels like a Mac app" scope is explicit.

### Verification (whole plan)

- Swift builds headlessly (`xcodebuild`); signature + notarization checked headlessly (`codesign --verify`, `spctl`, `stapler validate`).
- The actual **Finder preview** (Phase 1) and **Spotlight result** (Phase 2) are GUI surfaces — **Nathan is the visual verifier.**

### Execution discipline

Follows the project review→revise loop + execution conventions (`Studio/.claude/rules/Review-Discipline.md` + Pommora `CLAUDE.md`):

- **Adversarial review before ratifying.** V1 ran one round (it refuted the whole embed approach → re-architected to V2). The V2 standalone-helper approach + the two open items above run a **confirming review** (special weight on open item #1) before ratify. Re-version each round until clean.
- **Phase 0 is a hard gate.** No extension ships before the helper's Developer ID + notarization is in place.
- **One green commit per phase.** Never batch. **Re-assess between green commits.**
- **Verify yourself.** Confirm signature + registration against the real artifact — never on an agent's word.
- **Post-functional UIX review** on the real Finder preview before Phase 1 closeout.
- **Nathan is the GUI verifier.** **Swift code uses the `swiftui-expert-skill`.**
