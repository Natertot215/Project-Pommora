// Match a keydown against a command spec from the nexus `commands` map ("cmd+e", "ctrl+shift+k").
// Modifiers are exact — a spec without shift rejects a shifted press — so overlapping bindings
// can't double-fire.
export function matchesCommand(spec: string | undefined, e: KeyboardEvent): boolean {
  if (!spec) return false
  const parts = spec
    .toLowerCase()
    .split('+')
    .map((p) => p.trim())
    .filter(Boolean)
  if (parts.length === 0) return false
  const key = parts[parts.length - 1]
  const mods = new Set(parts.slice(0, -1))
  return (
    e.key.toLowerCase() === key &&
    e.metaKey === mods.has('cmd') &&
    e.ctrlKey === mods.has('ctrl') &&
    e.altKey === mods.has('alt') &&
    e.shiftKey === mods.has('shift')
  )
}
