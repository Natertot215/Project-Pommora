/** Numeric fractional order key: the value to give an item inserted between neighbors `a` and `b`
 *  (either null at a list end). Reordering rewrites only the moved item's key, so per-pin files never
 *  need a whole-list re-index. Precision exhausts after ~50 consecutive midpoints in one gap — an
 *  accepted ceiling (a pin set is small; a rebalance is out of scope). */
export function keyBetween(a: number | null, b: number | null): number {
  if (a === null && b === null) return 0
  if (a === null) return (b as number) - 1
  if (b === null) return a + 1
  return (a + b) / 2
}
