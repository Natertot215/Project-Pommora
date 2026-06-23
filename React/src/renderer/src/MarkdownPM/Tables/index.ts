import './Tables.css'
import type { Extension } from '@codemirror/state'
import { tableDecorations, tableDelimiterHider } from './decorations'
import { tableInput } from './input'

// One swappable extension. Resize (T8) appends here later.
export function tableExtension(): Extension {
  return [tableDecorations(), tableDelimiterHider(), tableInput()]
}
