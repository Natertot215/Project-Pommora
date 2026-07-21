// THE page-body autosave: one debounced writer PER PATH, shared by every host that edits a page
// (the main pane's PageView, the preview/tile PageEmbed). Hosts never own a private debounce —
// the same page open in two hosts would mean two uncoordinated writers to one file, last-writer-
// wins across a 400ms window. A path-keyed module map means the newest edit from ANY host owns
// the file's single pending write, and every teardown path (host unmount, nexus adopt, window
// close) flushes here instead of each host re-implementing the machinery.

const SAVE_DEBOUNCE_MS = 400

const pending = new Map<string, { body: string; timer: ReturnType<typeof setTimeout> }>()

/** (Re)schedule the page's debounced body write — the newest edit replaces any pending one. */
export function schedulePageSave(path: string, body: string): void {
  const p = pending.get(path)
  if (p) clearTimeout(p.timer)
  pending.set(path, {
    body,
    timer: setTimeout(() => void flushPageSave(path), SAVE_DEBOUNCE_MS),
  })
}

/** Write the path's pending body now (no-op without one). Awaitable, for hosts whose close path
 *  must land the write before the world changes. */
export function flushPageSave(path: string): Promise<void> {
  const p = pending.get(path)
  if (!p) return Promise.resolve()
  clearTimeout(p.timer)
  pending.delete(path)
  return window.nexus.updatePageBody(path, p.body).then(() => undefined)
}

/** Flush every pending page write. The nexus-adopt path (store.openVia) awaits this while the OLD
 *  root is still bound — a write landing after the flip would bind the new nexus and overwrite a
 *  same-relative-path file there (data loss). */
export function flushAllPageSaves(): Promise<void> {
  return Promise.all([...pending.keys()].map((p) => flushPageSave(p))).then(() => undefined)
}

// Closing the window inside the debounce must not drop the last edits. beforeunload can't await,
// but the IPC send itself gets out before teardown.
// (Guarded: node-env logic tests import store → this module without a window.)
if (typeof window !== 'undefined') {
  window.addEventListener('beforeunload', () => {
    for (const path of pending.keys()) void flushPageSave(path)
  })
}
