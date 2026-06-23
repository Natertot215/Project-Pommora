import './Tables.css'
import type { Extension } from '@codemirror/state'
import { tableDecorations, tableDelimiterHider } from './decorations'
import { tableInput } from './input'

// One swappable extension. Resize (T8) appends here later.
export function tableExtension(): Extension {
  return [tableDecorations(), tableDelimiterHider(), tableInput()]
}

// Widget-architecture rebuild (core slice): renders each table as a block-replace HTML widget over the
// canonical GFM source. Swappable for tableExtension() at the editor's call site while it's built up.
export { tableWidgetExtension } from './widget'
