import { describe, expect, it } from 'vitest'
import type { FormField, FormResponse } from '@/api/generated/model'
import { defaultValues, fieldKey } from './model'
import { reviewStale } from './stale'

const field = (name: string, value: unknown, extra: Partial<FormField> = {}): FormField => ({ name, param: name, label: name[0].toUpperCase() + name.slice(1), control: 'text', required: false, value, ...extra })

const response = (fields: FormField[]): FormResponse => ({
  resource: 'desks',
  id: '7',
  title: 'Edit desk',
  action: { method: 'patch', path: '/api/admin/desks/7' },
  form: { sections: [{ kind: 'inputs', fields }] },
  permissions: { update: true },
})

const valuesOf = (r: FormResponse) => defaultValues(r.form.sections.flatMap((s) => s.fields.map((f) => ({ key: fieldKey(f), field: f }))))

describe('reviewStale', () => {
  const opened = response([field('name', 'East'), field('region', 'NE'), field('notes', 'a')])

  it('lists your edits against the latest saved values', () => {
    const fresh = response([field('name', 'East'), field('region', 'NE'), field('notes', 'a')])
    const review = reviewStale(opened, fresh, { ...valuesOf(opened), name: 'East 2' })
    expect(review.changes).toEqual([{ key: 'name', label: 'Name', server: 'East', yours: 'East 2', conflict: false }])
    expect(review.carry).toEqual({ name: 'East 2' })
    expect(review.theirs).toEqual([])
  })

  it('flags a field both of you changed, and keeps their other changes out of the carry', () => {
    const fresh = response([field('name', 'West'), field('region', 'SW'), field('notes', 'a')])
    const review = reviewStale(opened, fresh, { ...valuesOf(opened), name: 'East 2' })
    expect(review.changes).toMatchObject([{ label: 'Name', server: 'West', yours: 'East 2', conflict: true }])
    expect(review.carry).toEqual({ name: 'East 2' })
    expect(review.theirs).toEqual(['Region'])
  })

  it('skips edits the server already has', () => {
    const fresh = response([field('name', 'East 2'), field('region', 'NE'), field('notes', 'a')])
    const review = reviewStale(opened, fresh, { ...valuesOf(opened), name: 'East 2' })
    expect(review.changes).toEqual([])
    expect(review.carry).toEqual({})
  })

  it('shows option labels and Yes/No instead of raw values', () => {
    const options = [{ label: 'North', value: 'n' }, { label: 'South', value: 's' }]
    const before = response([field('region', 'n', { control: 'select', options }), field('active', false, { control: 'boolean' })])
    const after = response([field('region', 's', { control: 'select', options }), field('active', false, { control: 'boolean' })])
    const review = reviewStale(before, after, { ...valuesOf(before), active: true })
    expect(review.changes).toMatchObject([{ label: 'Active', server: 'No', yours: 'Yes' }])
    expect(review.theirs).toEqual(['Region'])
  })

  it('ignores masked and hidden inputs', () => {
    const before = response([field('token', undefined, { masked: true }), field('secret', 'x', { control: 'hidden' })])
    const review = reviewStale(before, before, { token: 'new', secret: 'y' })
    expect(review.changes).toEqual([])
  })
})
