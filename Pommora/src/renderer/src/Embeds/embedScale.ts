/** THE embed scale knobs (G-10) — fixed amounts; resize is a viewport, never a scale (H-10).
 *  EMBED_SCALE is the ONE tunable; both embed kinds derive from it.
 *
 *  Page embeds: EMBED_SCALE drives the px-fixed dims (--mdpm-scale) and EMBED_ZOOM its
 *  log-curved text zoom (the MarkdownPM-tuned feel).
 *
 *  View embeds: base-size parity × the same embed zoom — the table's 13px body (tokens:
 *  text.body) is first normalized to the editor's 15px (MarkdownPM Styles.css), then
 *  zoomed exactly like a page embed, so both kinds read at ONE text level. */
export const EMBED_SCALE = 0.9
export const EMBED_ZOOM = 1 + Math.log2(EMBED_SCALE)
export const VIEW_EMBED_ZOOM = (15 / 13) * EMBED_ZOOM
