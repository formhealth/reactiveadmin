import { describe, expect, it } from 'vitest'
import type { Action } from '@/api/generated/model'
import { fallbackMode } from './presentation'

const action = (view?: Action['view']) => ({ key: 'a', label: 'A', kind: 'member', placement: 'header', method: 'get', enabled: true, view }) as Action

describe('fallbackMode', () => {
  it('uses the iframe for a view that runs script', () => expect(fallbackMode(action({ mode: 'iframe', path: '/x' }))).toBe('iframe'))
  it.each(['native', 'frame', 'custom'] as const)('uses the frame for %s', (mode) => expect(fallbackMode(action({ mode }))).toBe('frame'))
  it('uses the frame without a view', () => expect(fallbackMode(action())).toBe('frame'))
})
