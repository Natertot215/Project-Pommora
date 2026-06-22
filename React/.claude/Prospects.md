## Prospects — React

Ideas considered and deliberately parked — not on the active roadmap (`Framework.md`), not yet planned. Each notes what it is and why it's waiting; promote one into `Planning/` when it becomes active.

### Animated Syntax Reveal (Editor)

A quick slide/fade as MarkdownPM reveals a line's raw syntax under the caret, instead of the instant snap.

**Parked — not cleanly achievable against the current design.** The editor hides markers with a zero-width `Decoration.replace` (no DOM element — deliberately, so surrounding text never shifts), so there is nothing to animate *out* when the caret leaves; and revealed inline markers (`**`, `_`) are bare document text with no class to animate *in*. A true in-and-out slide would mean keeping every marker permanently mounted and animating its **width**, which jiggles the whole line's text on every caret move — worse than the clean snap, and it fights the no-shift design the editor is built around.

The realistic version is an **entry-only fade-in**: wrap revealed markers in a shared class and play a keyframe on mount, reusing the motion tokens; exit stays instant (CodeMirror removes the element with no exit hook). Revisit only if the soft-reveal feel is wanted enough to accept the entry-only asymmetry.
