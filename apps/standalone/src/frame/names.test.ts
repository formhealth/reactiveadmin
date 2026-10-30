// @vitest-environment jsdom
import { describe, expect, it } from 'vitest'
import { nameUnlabeledControls } from './names'

const named = (html: string) => {
  const root = Object.assign(document.createElement('div'), { innerHTML: html })
  document.body.append(root)
  nameUnlabeledControls(root)
  return root
}

describe('nameUnlabeledControls', () => {
  it('names a bare select from its name', () => {
    const root = named('<select name="state" id="state"><option>NY</option></select>')
    expect(root.querySelector('select')?.getAttribute('aria-label')).toBe('State')
  })

  it('reads the last segment of a nested param, and falls back to the id', () => {
    const root = named('<input name="plan[starts_on]"><textarea id="free_text"></textarea>')
    expect(root.querySelector('input')?.getAttribute('aria-label')).toBe('Starts on')
    expect(root.querySelector('textarea')?.getAttribute('aria-label')).toBe('Free text')
  })

  it('prefers a placeholder', () => {
    const root = named('<input name="q" placeholder="Search authors">')
    expect(root.querySelector('input')?.getAttribute('aria-label')).toBe('Search authors')
  })

  it('leaves labeled and already named controls alone', () => {
    const root = named(
      '<label for="a">Name</label><input id="a" name="a"><label>Wrapped <input name="b"></label><input name="c" aria-label="Custom"><input name="d" title="Titled">',
    )
    expect([...root.querySelectorAll('input')].map((input) => input.getAttribute('aria-label'))).toEqual([null, null, 'Custom', null])
  })

  it('skips hidden inputs and buttons, and controls with nothing to go on', () => {
    const root = named('<input type="hidden" name="token"><input type="submit" value="Go"><input>')
    expect([...root.querySelectorAll('input')].some((input) => input.hasAttribute('aria-label'))).toBe(false)
  })
})
