import { style } from '@vanilla-extract/css'

/** The card add-picker's rows sit tighter than the standard menu row — the property picker reads more
 *  compact (paddingBlock longhand overrides the base row's padding shorthand). */
export const compactRow = style({ paddingBlock: '3px' })
