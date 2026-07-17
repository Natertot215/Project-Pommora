// The flavor-swap morph seam: opening the NavWindow over a live page preview reads as ONE window
// changing shape — the store stashes the outgoing preview's rect here (synchronously, while it's
// still in the DOM), and the NavWindow's mount FLIPs from it. One-shot: consume clears the stash.

let stash: DOMRect | null = null

export const stashWindowMorph = (): void => {
  stash = document.querySelector('.pgpreview')?.getBoundingClientRect() ?? null
}

export const consumeWindowMorph = (): DOMRect | null => {
  const r = stash
  stash = null
  return r
}
