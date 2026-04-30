# SwiftUI / macOS Rules

Applies to any task touching Swift, SwiftUI, or macOS frontend code. These rules override default behavior.

## Source authority

- Authoritative sources, in this order:
  1. Apple Human Interface Guidelines — https://developer.apple.com/design/human-interface-guidelines/
  2. Apple Developer Documentation — https://developer.apple.com/documentation/swiftui/
  3. URLs Nathan provides in-conversation
- Never rely on training memory alone for any API signature, modifier behavior, availability version, or HIG rule. Fetch the relevant Apple page via WebFetch and cite it before stating the claim or writing the code.
- If the relevant Apple doc cannot be fetched, stop and report. Do not guess. Do not approximate from memory.
- Community sources (Stack Overflow, blogs, GitHub issues) are not authoritative. They may seed an approach, but every claim derived from them must be verified against Apple docs before being committed to code.

## Component constraints

- Use only official SwiftUI components and modifiers available in the project's minimum deployment target. Confirm availability via the "Availability" section of each component's Apple doc page.
- No third-party UI libraries.
- No UIKit/AppKit bridges (`NSViewRepresentable`, `UIViewRepresentable`) unless the required behavior is provably impossible in pure SwiftUI for the target version. In that case: cite the Apple doc confirming the gap, surface it to Nathan, wait for confirmation before proceeding.

## HIG adherence

- Before designing or modifying any UI surface, fetch the relevant HIG page(s) for macOS and the specific component category (e.g. sidebars, toolbars, menus, sheets, popovers, controls).
- Match HIG specs for spacing, typography, color, control sizing, window chrome, and accessibility.
- Dynamic Type, light/dark mode, and full keyboard accessibility are non-optional.

## Build → screenshot → review loop

Run after every UI-affecting change. No exceptions.

1. Build. Resolve all errors and UI-related warnings before proceeding.
2. Launch the app.
3. Navigate to the screen affected by the change. If automated navigation isn't feasible, ask Nathan to navigate and confirm before capture.
4. Capture a screenshot of the running app window. Use `screencapture` on macOS — prefer window-targeted capture via window ID over full-screen:
   ```bash
   mkdir -p ./screenshots
   screencapture -l$(osascript -e 'tell app "System Events" to tell process "<AppName>" to id of window 1') \
     ./screenshots/$(date +%Y%m%d-%H%M%S)-<short-description>.png
   ```
   Save to `./screenshots/` in the project root. Create the folder if missing. Filename: `YYYYMMDD-HHMMSS-<short-description>.png`.
5. View the screenshot. Compare against:
   - the intended change
   - the relevant HIG page (re-fetch if not already loaded this session)
   - an adjacent unmodified screen for cohesion (typography, spacing, color, control style)
6. If anything is off — visual misalignment, HIG drift, inconsistency, regression — iterate. Return to step 1.

If the change involves multiple states (hover, selected, focused, error, loading, empty), capture each state separately.

## Stopping criteria

Work is not complete until ALL are true:

- Build succeeds with zero warnings related to the change.
- Every modified screen has been screenshotted and visually reviewed.
- Every UI element on every modified screen has been cross-referenced against its HIG page.
- An adjacent unmodified screen has been screenshotted and compared for app-wide cohesion.
- All HIG deviations are explicitly justified and surfaced to Nathan — not silently accepted.

If any fail, work is not done. Continue iterating. Do not stop to ask if it's "good enough" mid-loop — finish, then report.

## Reporting

On completion, report:

- Every screenshot captured (path + what it shows + state).
- Every Apple doc URL cross-referenced.
- Any HIG deviation and its justification.
- One of these closing lines, verbatim:
  - **`Build clean, screenshots reviewed, HIG verified — finalized.`** (truly done)
  - **`Outstanding: <list>`** (not done; list what remains)
