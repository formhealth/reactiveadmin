import { describe, expect, it } from 'vitest'
import { available, isChord, keyGlyph, plainShortcut, shortcuts } from './shortcuts'

const ids = (screen: Parameters<typeof available>[0], caps: Parameters<typeof available>[1]) => available(screen, caps).map((s) => s.id)

describe('available', () => {
  it('lists only the global shortcuts off the index', () => {
    expect(ids('any', ['rows', 'filters', 'batch'])).toEqual(['palette', 'help'])
  })

  it('hides shortcuts whose controls are missing', () => {
    expect(ids('index', [])).toEqual(['palette', 'help'])
    expect(ids('index', ['rows'])).toEqual(['palette', 'help', 'down', 'up', 'open'])
    expect(ids('index', ['filters'])).toEqual(['palette', 'help', 'filter'])
  })

  it('offers selecting only with rows and batch actions', () => {
    expect(ids('index', ['batch'])).not.toContain('select')
    expect(ids('index', ['rows', 'batch'])).toContain('select')
  })
})

describe('plainShortcut', () => {
  it('maps every alternative key to its shortcut, for handled ids only', () => {
    expect(plainShortcut('ArrowDown', ['down', 'up'])?.id).toBe('down')
    expect(plainShortcut('k', ['down', 'up'])?.id).toBe('up')
    expect(plainShortcut('x', ['down', 'up'])).toBeUndefined()
  })

  it('leaves chords to isChord, so a bare k never opens the palette', () => {
    expect(plainShortcut('k', ['palette'])).toBeUndefined()
  })
})

describe('isChord', () => {
  const palette = shortcuts.find((s) => s.id === 'palette')!
  const press = (key: string, mods: { metaKey?: boolean; ctrlKey?: boolean } = {}) => ({ key, metaKey: false, ctrlKey: false, ...mods })

  it('needs Cmd or Ctrl, in either case', () => {
    expect(isChord(palette, press('k', { metaKey: true }))).toBe(true)
    expect(isChord(palette, press('K', { ctrlKey: true }))).toBe(true)
    expect(isChord(palette, press('k'))).toBe(false)
  })
})

describe('registry', () => {
  it('binds each plain key once', () => {
    const bound = shortcuts.filter((s) => !s.mod).flatMap((s) => s.keys)
    expect(new Set(bound).size).toBe(bound.length)
  })
})

describe('keyGlyph', () => {
  it('shows arrows as glyphs and letters uppercase', () => {
    expect([keyGlyph('ArrowUp'), keyGlyph('j'), keyGlyph('Enter'), keyGlyph('?')]).toEqual(['↑', 'J', 'Enter', '?'])
  })
})
