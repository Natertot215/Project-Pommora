// The table feature: a block-replace widget renders each Markdown table as an interactive HTML table over
// the canonical GFM source — cells edit via nested CodeMirror editors; the source stays in the document.
export { tableWidgetExtension, applySavedHeadingCols, type TableHeadingColsApi } from './widget'
