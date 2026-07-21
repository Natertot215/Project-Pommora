// Suite-wide environment shims. jsdom implements no layout, so hit-testing APIs the drag
// engines call (spring-load's elementFromPoint) are absent — stub them to "nothing there"
// rather than letting pointer-driving tests die on an uncaught TypeError.
if (typeof document !== 'undefined' && !document.elementFromPoint) {
  document.elementFromPoint = () => null
}
