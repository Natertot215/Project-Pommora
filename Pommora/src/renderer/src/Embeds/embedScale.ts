/** THE embed scale knob (G-10): ONE fixed amount for every embed kind — page embeds
 *  and view embeds must read at the same visual level; resize is a viewport, never a
 *  scale (H-10). The zoom maps the scale through a log curve (the MarkdownPM-tuned
 *  feel) — consumers apply EMBED_ZOOM, never the raw scale. */
export const EMBED_SCALE = 0.9
export const EMBED_ZOOM = 1 + Math.log2(EMBED_SCALE)
