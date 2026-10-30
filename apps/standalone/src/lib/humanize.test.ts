import { describe, expect, it } from 'vitest'
import { humanize, pluralLabel } from './humanize'

describe('pluralLabel', () => {
  it('is the manifest label once it has loaded', () => expect(pluralLabel({ plural_label: 'Admin Policies' }, 'admin_policies')).toBe('Admin Policies'))

  it('never falls back to the raw key', () => {
    expect(pluralLabel(undefined, 'admin_policies')).toBe('Admin policies')
    expect(humanize('admin_policies')).toBe('Admin policies')
  })
})
