// A hook for the nexus-adopt path (store.openVia) to flush the active page editor's PENDING body write
// while the OLD root is still bound. Without it the editor's unmount-flush — fired by the selection-clear
// AFTER adopt has flipped the root — lands the old page's body in the NEW nexus, overwriting a file at the
// same relative path there (data loss). PageView registers its awaitable flush while mounted; openVia
// awaits it before the switch, and because the flush clears the pending save, the unmount-flush is a no-op.

let flush: (() => Promise<void>) | null = null

/** PageView registers its awaitable flush while mounted; passes null on unmount. */
export function registerPageFlush(fn: (() => Promise<void>) | null): void {
  flush = fn
}

/** Flush + await the active page's pending write (no-op when no page is mounted). */
export function flushActivePage(): Promise<void> {
  return flush?.() ?? Promise.resolve()
}
