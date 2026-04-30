# Pommora — Project Context

A generic native macOS app skeleton built against the macOS 26 design language. This file is the thin operational hub. The substance lives in the linked files below — read those before planning or coding. The skeleton has no product features yet; it provides a verified `NavigationSplitView` shell, a `.searchable` sidebar, a placeholder middle column, and a `Components/` library of swiftinterface-verified SwiftUI primitives ready to be assembled into features.

## Stack

Swift 6.x, SwiftUI shell, SwiftData (local only — no cloud, no accounts), macOS 26 only. Xcode project at `Pommora/Pommora.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup` — any `.swift` file added to `Pommora/Pommora/` (or `PommoraTests/`, `PommoraUITests/`) is auto-compiled. No `project.pbxproj` edits needed.

## Workflow

**Edit Swift in VS Code, run in Xcode.** Nathan strongly prefers to avoid Xcode for editing.

| Task | Where |
|---|---|
| Edit `.swift` files | VS Code (Swift extension by swiftlang) |
| Build (CLI) | `cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx` |
| Run / debug | Xcode `Cmd+R` |
| SwiftUI Previews | Xcode only |
| Edit `Info.plist`, `*.entitlements`, `*.xcassets/Contents.json` | VS Code (text formats) |
| Add a new `.swift` file | Create it in `Pommora/Pommora/<subdir>/` — synchronized groups pick it up |
| Adjust target settings, schemes, capabilities | Xcode (rare) |

## File index

Read the right file for the work you're about to do.

| File | Purpose | Read before |
|---|---|---|
| [`framework.md`](framework.md) | Vision, current state, scope, standing constraints, behavior contracts, deferred decisions, planning checklist | Planning any feature, scoping a task, making architectural decisions |
| [`feedback.md`](feedback.md) | Persistent behavior corrections from Nathan | Every session start |
| [`lessons.md`](lessons.md) | Failure patterns (L-001…L-006) — never make the same mistake twice | The kind of work that previously failed (UI changes, SwiftUI APIs, NavigationSplitView, file paths, drag/drop) |
| [`swift-uix-rules.md`](swift-uix-rules.md) | SwiftUI / macOS rules — source authority, component constraints, HIG adherence, build→screenshot→review loop | **Mandatory** — see rule below |
| [`components-reference.md`](components-reference.md) | Catalogue of verified SwiftUI components in `Pommora/Pommora/Components/` — names, swiftinterface citations, idiomatic snippets | Adding any new SwiftUI surface — check here first before writing from memory |
| [`session-recaps/`](session-recaps/) | Dated summaries of significant sessions | When picking up state from a prior session |

## MANDATORY rule for Swift / SwiftUI / macOS work

**Any task touching Swift, SwiftUI, or macOS frontend code → load and follow [`swift-uix-rules.md`](swift-uix-rules.md) before writing or modifying any code. Non-negotiable.**

This includes the build → screenshot → review loop after every UI-affecting change. Closing line for completed UI work must be one of the verbatim phrases specified in that file.

## Memory protocol

Memory is mandatory, not optional. Skipping these triggers is how the same mistakes happen twice.

**When to write:**

- Nathan corrects your behavior → append to [`feedback.md`](feedback.md) immediately, before moving on.
- A bug or mistake is discovered and fixed → append a dated incident to the matching L-00X entry in [`lessons.md`](lessons.md). If it's a new failure pattern, add a new L-00X entry.
- An architectural constraint surfaces, or skeleton scope shifts → update [`framework.md`](framework.md) (Skeleton scope, Standing constraints, or Component categories).
- Nathan directs you to record the session → create a new file in [`session-recaps/`](session-recaps/) named `Session DD-MM-YY (#).md` (see that folder's README).

**What to write:** the non-obvious part. If it's in the code or git history, don't duplicate it. Write the *why*, the *constraint*, the *decision that surprised you*, or the *mistake pattern* — so future sessions don't have to rediscover it.

Also write to `~/.claude/projects/<proj>/memory/` for auto-memory recall when the fact is about *how to work with Nathan* or a *non-obvious correction* (per the three-tier rule in `~/.claude/CLAUDE.md`).

## Things we do NOT do

- Don't write to disk on every edit. Auto-save is OFF in MVP and stays OFF in v1.1.
- Don't invent `// MARK:` comment headers in short files.
- Don't add doc-comments to obvious symbols.
- Don't add error handling for impossible cases — force-unwraps inside controlled `do/catch` are fine.
- Don't add backwards-compat shims — macOS 26 is the only target.
- Don't reach for `.font(.system(size:))` or hand-mixed `Color(red:green:blue:)` — use semantic primitives. (See L-001.)
- Don't propose AppKit wraps (`NSViewRepresentable`) in v1.0 — Swift-only until v1.1.
