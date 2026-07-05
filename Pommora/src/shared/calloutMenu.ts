// The callout grip's native right-click menu contract. Mirrors the table grip menu: the renderer pops it
// off the gutter grip, main builds it, the chosen action comes back. Only one action today (delete), but
// the channel is the seam for future callout actions.
export type CalloutMenuAction = 'callout:delete'
