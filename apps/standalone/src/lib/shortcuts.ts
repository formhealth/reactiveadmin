export type ShortcutId = 'palette' | 'help' | 'filter' | 'down' | 'up' | 'open' | 'select'
export type Screen = 'any' | 'index'
export type Capability = 'rows' | 'filters' | 'batch'

export type Shortcut = {
  id: ShortcutId
  label: string
  // `KeyboardEvent.key` values; the first is the one shown. With `mod`, they go with Cmd or Ctrl.
  keys: string[]
  mod?: boolean
  screen: Screen
  needs?: Capability[]
}

export const shortcuts: Shortcut[] = [
  { id: 'palette', label: 'Open the command palette', keys: ['k'], mod: true, screen: 'any' },
  { id: 'help', label: 'Show keyboard shortcuts', keys: ['?'], screen: 'any' },
  { id: 'filter', label: 'Focus the filters', keys: ['/'], screen: 'index', needs: ['filters'] },
  { id: 'down', label: 'Move to the next row', keys: ['j', 'ArrowDown'], screen: 'index', needs: ['rows'] },
  { id: 'up', label: 'Move to the previous row', keys: ['k', 'ArrowUp'], screen: 'index', needs: ['rows'] },
  { id: 'open', label: 'Open the current row', keys: ['Enter'], screen: 'index', needs: ['rows'] },
  { id: 'select', label: 'Select the current row', keys: ['x'], screen: 'index', needs: ['rows', 'batch'] },
]

export const available = (screen: Screen, caps: Capability[]) =>
  shortcuts.filter((s) => (s.screen === 'any' || s.screen === screen) && (s.needs ?? []).every((c) => caps.includes(c)))

export const plainShortcut = (key: string, ids: ShortcutId[]) => shortcuts.find((s) => !s.mod && ids.includes(s.id) && s.keys.includes(key))

export const isChord = (s: Shortcut, e: Pick<KeyboardEvent, 'key' | 'metaKey' | 'ctrlKey'>) =>
  !!s.mod && (e.metaKey || e.ctrlKey) && s.keys.includes(e.key.toLowerCase())

const GLYPHS: Record<string, string> = { ArrowDown: '↓', ArrowUp: '↑' }
export const keyGlyph = (key: string) => GLYPHS[key] ?? (key.length === 1 ? key.toUpperCase() : key)
