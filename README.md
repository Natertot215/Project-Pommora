# Pommora

A native macOS markdown and plaintext editor built against the macOS 26 design language.

Folder-organized, not database-organized. Files stay where you put them on disk — Pommora holds references, not copies. Built for macOS 26 with SwiftUI, SwiftData, and (where SwiftUI falls short) AppKit.

## Status

**Pre-1.0** — under active development. See [`PRD`](PRD) for the product spec and `/Users/nathantaichman/.claude/plans/help-me-turn-this-deep-whistle.md` for the v1.0 implementation plan.

## Build

Requires:
- macOS 26
- Xcode (full installation, not just Command Line Tools)

```bash
git clone <this repo>
cd "Project Pommora/Pommora"
xcodebuild -scheme Pommora -configuration Debug build
```

To run with the debugger, open `Pommora.xcodeproj` in Xcode and press **Cmd+R**.

## Develop

Day-to-day code editing happens in **VS Code** with the official Swift extension (which bundles `sourcekit-lsp`). Xcode is opened only for `Cmd+R` runs and SwiftUI Previews. See [`.claude/CLAUDE.md`](.claude/CLAUDE.md) for the full workflow rules.

## Distribution

Open-source, unsigned. On first launch, right-click the `.app` → Open to bypass Gatekeeper. App Store / signing / notarization decisions deferred.

## License

TBD.
