// The one debounced-sidecar machine: a per-nexus JSON file whose writes coalesce (the newest
// payload supersedes any pending one), with the quit/switch drain contract every synced sidecar
// shares. The pending payload carries its own root, so a late flush always lands in the nexus it
// was recorded for. tabsState, navState, and previewState all run on this.

import { mkdir } from 'node:fs/promises'
import { nexusDir } from '../paths'
import { writeJson } from './atomicWrite'
import { serializeOnFile } from './fileLock'

export interface DebouncedSidecar<T> {
  /** Debounced write — the per-mutation path. Newest payload wins the burst. */
  schedule(root: string, payload: T): void
  /** Immediate write; supersedes and cancels any pending debounced payload so a stale one can't
   *  land after it. */
  writeNow(root: string, payload: T): Promise<void>
  /** A debounced payload is still queued (not yet driven to disk). */
  hasQueued(): boolean
  /** Anything still owed to disk — a queued debounce OR a write still settling (tracked immediate
   *  writes included). The quit gate + nexus-switch drain check this. */
  hasPending(): boolean
  /** Drive a queued payload to disk and await that one write (not the whole drain). */
  flushQueued(): Promise<void>
  /** Drain EVERYTHING owed: flush the debounce, wait out in-flight writes, looping so a write
   *  landing mid-drain is caught too. */
  flush(): Promise<void>
  /** Fold an external write into the drain accounting (e.g. a sibling file's immediate writes
   *  that share this sidecar's quit gate). */
  track<P extends Promise<unknown>>(p: P): P
}

export function debouncedSidecar<T>(opts: {
  path: (root: string) => string
  debounceMs: number
  /** Names the sidecar in the debounced-flush failure log. */
  label: string
}): DebouncedSidecar<T> {
  const inFlight = new Set<Promise<unknown>>()
  let pending: { root: string; payload: T } | null = null
  let timer: ReturnType<typeof setTimeout> | null = null

  const clearTimer = (): void => {
    if (timer) {
      clearTimeout(timer)
      timer = null
    }
  }
  const track = <P extends Promise<unknown>>(p: P): P => {
    inFlight.add(p)
    const clear = (): void => void inFlight.delete(p)
    p.then(clear, clear)
    return p
  }
  const write = (root: string, payload: T): Promise<void> => {
    const path = opts.path(root)
    return track(
      serializeOnFile(path, async () => {
        await mkdir(nexusDir(root), { recursive: true })
        await writeJson(path, payload)
      }),
    )
  }
  const flushQueued = async (): Promise<void> => {
    clearTimer()
    const p = pending
    pending = null
    if (p) await write(p.root, p.payload)
  }
  return {
    schedule(root, payload) {
      pending = { root, payload }
      clearTimer()
      timer = setTimeout(
        () =>
          void flushQueued().catch((e) =>
            console.error(`${opts.label} debounced flush failed:`, e),
          ),
        opts.debounceMs,
      )
    },
    async writeNow(root, payload) {
      clearTimer()
      pending = null
      await write(root, payload)
    },
    hasQueued: () => pending !== null,
    hasPending: () => pending !== null || inFlight.size > 0,
    flushQueued,
    async flush() {
      while (pending !== null || inFlight.size > 0) {
        await flushQueued()
        await Promise.allSettled([...inFlight])
      }
    },
    track,
  }
}
