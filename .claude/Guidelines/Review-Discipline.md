## Review Discipline

The review → revise loop is **standard, not optional**. Every spec and plan runs it before it's called done.

**Never declare a doc "bulletproof," "final," or "fine" until an adversarial review has proven it.** Confidence is earned through evidence, not asserted up front. Stating "this is solid" before the review is the exact failure the cornerstone forbids — claim something true, build on it, discover later it was never true.

**Why:** The ItemsV2 Item Window spec was called "fine" at V1, then **five** review rounds each surfaced real, build-breaking issues none visible from the doc alone — a duplicate-surface bug (a pinned property showing in two places + the Add-Property menu), body-on-close + title-on-blur data loss, the overlay re-host's true cost vs the kept window, a cited UI precedent (`StatusGroupsEditor` as a checkbox list) that didn't exist, a live `.null`-written-to-disk bug in the table editors, and the pooled-cap engine's muting/precedence holes.

**How to apply:**

- After writing or revising any spec/plan, dispatch an adversarial review (compile-grounding + logic/coverage at minimum; add UIX→data + over-engineering for anything load-bearing) **before** presenting it as ratified.
- Phrase status honestly: "written, pending review" vs "review-certified" — never "bulletproof" pre-review.
- Fold each round's findings and re-version (V1 → V2 …) per convention; the loop runs until a round comes back genuinely clean, then ratify.
- Ground every `file:line` claim against real code before relying on it; a doc claim is a hypothesis until the code proves it.
- **The discipline is the deliverable.**
