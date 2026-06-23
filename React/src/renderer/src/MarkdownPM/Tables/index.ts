import './Tables.css'
import type { Extension } from '@codemirror/state'
import { tableDecorations, tableDelimiterHider } from './decorations'

// One swappable extension. Later slices append input/nav (T6) and resize (T8) here.
export function tableExtension(): Extension {
  return [tableDecorations(), tableDelimiterHider()]
}
