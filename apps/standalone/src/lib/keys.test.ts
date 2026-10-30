import { describe, expect, it } from 'vitest'
import { uniqueKeys } from './keys'

describe('uniqueKeys', () => {
  it('leaves distinct keys alone', () => {
    expect(uniqueKeys(['a', 'b'])).toEqual(['a', 'b'])
  })

  it('numbers repeats from the second occurrence', () => {
    expect(uniqueKeys(['notes', 'notes', 'tasks', 'notes'])).toEqual(['notes', 'notes-2', 'tasks', 'notes-3'])
  })

  it('skips a number a later key already uses', () => {
    expect(uniqueKeys(['notes', 'notes', 'notes-2'])).toEqual(['notes', 'notes-2', 'notes-2-2'])
  })
})
