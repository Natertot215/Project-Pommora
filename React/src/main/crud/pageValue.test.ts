import { describe, it, expect } from 'vitest'
import { stripPageValue, replacePageValue } from './pageValue'

const page = (props: string) => `---\nid: p1\nproperties:\n${props}---\nbody\n`

describe('stripPageValue', () => {
  it('select: deletes the key iff the value matches', () => {
    const hit = stripPageValue(page('  prop_s: Urgent\n'), 'prop_s', 'Urgent', 'select')
    expect(hit).toContain('body')
    expect(hit).not.toContain('prop_s')
    expect(stripPageValue(page('  prop_s: Other\n'), 'prop_s', 'Urgent', 'select')).toBeNull()
  })

  it('status: matches the $status object', () => {
    const c = stripPageValue(page('  prop_s:\n    $status: Active\n'), 'prop_s', 'Active', 'status')
    expect(c).not.toBeNull()
    expect(c).not.toContain('$status')
  })

  it('multi_select: filters the array, deletes the key only when empty', () => {
    const kept = stripPageValue(page('  prop_m:\n    - a\n    - x\n    - b\n'), 'prop_m', 'x', 'multi_select')
    expect(kept).toContain('a')
    expect(kept).toContain('b')
    expect(kept).not.toContain('- x')
    const empty = stripPageValue(page('  prop_m:\n    - x\n'), 'prop_m', 'x', 'multi_select')
    expect(empty).not.toBeNull()
    expect(empty).not.toContain('prop_m')
  })
})

describe('replacePageValue (rename cascade)', () => {
  it('select: swaps the matching value', () => {
    expect(replacePageValue(page('  prop_s: Urgent\n'), 'prop_s', 'Urgent', 'Critical', 'select')).toContain('Critical')
  })

  it('status: swaps inside the $status object', () => {
    const c = replacePageValue(page('  prop_s:\n    $status: Active\n'), 'prop_s', 'Active', 'Doing', 'status')
    expect(c).toContain('Doing')
    expect(c).not.toContain('Active')
  })

  it('multi_select: swaps one element in place', () => {
    const c = replacePageValue(page('  prop_m:\n    - a\n    - x\n'), 'prop_m', 'x', 'y', 'multi_select')
    expect(c).toContain('- y')
    expect(c).not.toContain('- x')
  })

  it('returns null when the page does not hold the value', () => {
    expect(replacePageValue(page('  prop_s: Other\n'), 'prop_s', 'Urgent', 'Critical', 'select')).toBeNull()
  })
})
