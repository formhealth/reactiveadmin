import { describe, expect, it } from 'vitest'
import type { FormField, FormSection } from '@/api/generated/model'
import { postForm, deskForm, desks } from '@/mocks/forms'
import { posts } from '@/mocks/fixtures'
import {
  activeFields,
  collectEntries,
  dayBounds,
  defaultValues,
  fieldKey,
  initialRows,
  changeSummary,
  initialValue,
  isCompact,
  loadedKey,
  mapErrors,
  mapRowErrors,
  newRow,
  nextRowIndex,
  rowChanges,
  submitValue,
  validate,
  type ActiveField,
} from './model'
import { paramsToObject } from './params'

const field = (f: Partial<FormField> & Pick<FormField, 'control'>): FormField => ({ name: 'f', label: 'F', required: false, param: 'r[f]', ...f })
const active = (...fields: FormField[]): ActiveField[] => fields.map((f) => ({ key: fieldKey(f), field: f }))
const check = (f: FormField, value: unknown) => validate(active(f), { [fieldKey(f)]: value })[fieldKey(f)]

describe('fieldKey', () => {
  it('flattens params into names react-hook-form will not parse as paths', () => {
    expect(fieldKey({ name: 'x', param: 'desk[desk_members_attributes][0][user_email]' })).toBe('desk__desk_members_attributes__0__user_email')
    expect(fieldKey({ name: 'x', param: 'desk[region_ids][]' })).toBe('desk__region_ids')
    expect(fieldKey({ name: 'a.b', param: null })).toBe('a_b')
  })
})

describe('initialValue / submitValue', () => {
  it('normalizes server values for inputs', () => {
    expect(initialValue(field({ control: 'text', value: null }))).toBe('')
    expect(initialValue(field({ control: 'number', value: 4 }))).toBe('4')
    expect(initialValue(field({ control: 'boolean', value: 'true' }))).toBe(true)
    expect(initialValue(field({ control: 'date', value: '2026-10-16T12:00:00Z' }))).toBe('2026-10-16')
    expect(initialValue(field({ control: 'time', value: '2000-01-01T14:30:00Z' }))).toBe('14:30')
    expect(initialValue(field({ control: 'checkboxes', value: ['a', 1] }))).toEqual(['a', '1'])
    expect(initialValue(field({ control: 'json', value: { a: 1 } }))).toBe('{\n  "a": 1\n}')
    expect(initialValue(field({ control: 'json', value: null }))).toBe('')
  })

  it('submits structured json, numbers, and omits an unchosen file', () => {
    expect(submitValue(field({ control: 'json' }), '{"a":1}')).toEqual({ a: 1 })
    expect(submitValue(field({ control: 'json' }), '  ')).toBeNull()
    expect(submitValue(field({ control: 'number' }), '12.5')).toBe(12.5)
    expect(submitValue(field({ control: 'number' }), '')).toBe('')
    expect(submitValue(field({ control: 'file' }), null)).toBeUndefined()
  })
})

describe('indexed rows of a repeated fields_for group', () => {
  it('posts each row under its own index-keyed param', () => {
    const rows = [0, 1, 2].map((i) => field({ control: 'text', name: 'email', param: `r[contacts][${i}][email]`, value: `c${i}@example.com` }))
    const section: FormSection = { title: null, kind: 'inputs', fields: rows }
    const fields = activeFields([section], {})
    const body = paramsToObject(collectEntries([section], {}, defaultValues(fields)))

    expect(new Set(fields.map((f) => f.key)).size).toBe(3)
    expect(body).toEqual({ r: { contacts: { 0: { email: 'c0@example.com' }, 1: { email: 'c1@example.com' }, 2: { email: 'c2@example.com' } } } })
  })
})

describe('date limits', () => {
  const limited = (control: 'date' | 'datetime', min?: string, max?: string) => field({ control, input_html: { min, max } })

  it('reads the allowed days, an instant in local time for a datetime', () => {
    expect(dayBounds(limited('date', '2026-10-10', '2026-10-22'))).toEqual({ min: '2026-10-10', max: '2026-10-22' })
    expect(dayBounds(limited('datetime', '2026-10-12T00:00:00Z'))).toEqual({ min: expect.stringMatching(/^2026-10-1[12]$/), max: undefined })
    expect(dayBounds(field({ control: 'date' }))).toEqual({ min: undefined, max: undefined })
  })

  it('rejects days outside the range and leaves blanks to required', () => {
    const range = limited('date', '2026-10-10', '2026-10-22')
    expect(check(range, '2026-10-09')).toBe('Choose a date from 2026-10-10 to 2026-10-22')
    expect(check(range, '2026-10-23')).toBe('Choose a date from 2026-10-10 to 2026-10-22')
    expect(check(range, '2026-10-10')).toBeUndefined()
    expect(check(range, '2026-10-22')).toBeUndefined()
    expect(check(range, '')).toBeUndefined()
    expect(check(limited('date', '2026-10-10'), '2026-10-01')).toBe('Choose a date on or after 2026-10-10')
    expect(check(limited('date', undefined, '2026-10-10'), '2026-10-11')).toBe('Choose a date on or before 2026-10-10')
  })

  it('applies the day limits to a datetime', () => {
    expect(check(limited('datetime', '2026-10-12T12:00:00Z'), '2026-10-01T09:00')).toMatch(/^Choose a date on or after/)
    expect(check(limited('datetime', '2026-10-12T12:00:00Z'), '2026-10-20T09:00')).toBeUndefined()
  })
})

describe('validate (schema builder)', () => {
  it('requires values', () => {
    expect(check(field({ control: 'text', required: true }), '  ')).toBe('Required')
    expect(check(field({ control: 'text', required: true }), 'x')).toBeUndefined()
    expect(check(field({ control: 'text' }), '')).toBeUndefined()
    expect(check(field({ control: 'multiselect', required: true }), [])).toBe('Required')
  })

  it('checks email, url and number formats only when filled', () => {
    expect(check(field({ control: 'email' }), 'nope')).toMatch(/email/)
    expect(check(field({ control: 'email' }), 'a@b.co')).toBeUndefined()
    expect(check(field({ control: 'url' }), 'example.com')).toMatch(/URL/)
    expect(check(field({ control: 'url' }), 'https://example.com')).toBeUndefined()
    expect(check(field({ control: 'number' }), 'abc')).toBe('Enter a number')
    expect(check(field({ control: 'number' }), '')).toBeUndefined()
  })

  it('applies min, max and maxlength from input_html', () => {
    const n = field({ control: 'number', input_html: { min: 1, max: 5 } })
    expect(check(n, '0')).toBe('Enter a number from 1 to 5')
    expect(check(n, '6')).toBe('Enter a number from 1 to 5')
    expect(check(n, '3')).toBeUndefined()
    expect(check(field({ control: 'text', input_html: { maxlength: 3 } }), 'abcd')).toBe('Use 3 characters or fewer')
  })

  it('reports invalid json with the parser message', () => {
    expect(check(field({ control: 'json' }), '{"a":')).toMatch(/^Invalid JSON/)
    expect(check(field({ control: 'json' }), '{"a":1}')).toBeUndefined()
    expect(check(field({ control: 'json', required: true }), '')).toBe('Required')
  })

  it('ignores disabled, hidden and html fields', () => {
    const fields = active(field({ control: 'text', required: true, disabled: true }), field({ name: 'h', param: 'r[h]', control: 'hidden' }))
    expect(validate(fields, {})).toEqual({})
  })
})

describe('content fields', () => {
  const content = field({ name: 'content_1', param: null, label: '', control: 'content', layout: [{ type: 'text', text: 'Note' }] })
  const sections: FormSection[] = [{ kind: 'inputs', fields: [content, field({ name: 'a', param: 'r[a]', control: 'text', required: true })] }]

  it('is no input: no value, no validation, and nothing in the write', () => {
    const fields = activeFields(sections, initialRows(sections))

    expect(Object.keys(defaultValues(fields))).toEqual(['r__a'])
    expect(validate(fields, { r__a: 'x' })).toEqual({})
    expect(collectEntries(sections, initialRows(sections), { r__a: 'x' })).toEqual([['r[a]', 'x']])
  })
})

describe('collectEntries', () => {
  it('builds the post payload with parsed json', () => {
    const { sections } = postForm(posts[1]).form
    const rows = initialRows(sections)
    const values = defaultValues(activeFields(sections, rows))
    const body = paramsToObject(collectEntries(sections, rows, values)) as { post: Record<string, unknown> }
    expect(body.post.editor_id).toBe('2')
    expect(body.post.published_on).toBe(posts[1].published_on)
    expect(body.post.details).toMatchObject({ author_state: 'MA', tags: ['news'] })
  })

  it('nests has_many rows: keeps ids, marks removed rows for destroy and numbers new rows after existing ones', () => {
    const { sections } = deskForm(desks[0]).form
    const hasMany = sections.findIndex((s) => s.kind === 'has_many')
    let rows = initialRows(sections)
    rows = { ...rows, [hasMany]: [{ ...rows[hasMany][0], removed: true }, rows[hasMany][1], newRow(sections[hasMany], nextRowIndex(rows[hasMany]))] }
    const fields = activeFields(sections, rows)
    const values = { ...defaultValues(fields), desk__desk_members_attributes__2__user_email: 'new@example.com' }
    const { desk } = paramsToObject(collectEntries(sections, rows, values)) as { desk: { desk_members_attributes: Record<string, Record<string, unknown>> } }
    expect(desk.desk_members_attributes[0]).toEqual({ id: 'pu-1', _destroy: '1' })
    expect(desk.desk_members_attributes[1]).toEqual({ id: 'pu-2', user_email: 'marcus.johnson@example.com' })
    expect(desk.desk_members_attributes[2]).toEqual({ user_email: 'new@example.com' })
  })

  it('sends nothing for an unselected radio, as a browser does', () => {
    const radio = field({ name: 'kind', control: 'radio', param: 'r[kind]' })
    const key = fieldKey(radio)
    expect(collectEntries([{ kind: 'inputs', fields: [radio] } as FormSection], {}, { [key]: '' })).toEqual([])
    expect(collectEntries([{ kind: 'inputs', fields: [radio] } as FormSection], {}, { [key]: 'a' })).toEqual([['r[kind]', 'a']])
  })

  describe('a summarized json field', () => {
    const summarized = field({ name: 'details', param: 'r[details]', control: 'json', required: true, value: null, summary: { kind: 'object', keys: ['a'], size: 9 } })
    const key = fieldKey(summarized)
    const entries = (values: Record<string, unknown>) => collectEntries([{ kind: 'inputs', fields: [summarized] } as FormSection], {}, values)

    it('is omitted until it is loaded and edited, and is not required', () => {
      expect(entries({ [key]: '' })).toEqual([])
      expect(validate(active(summarized), { [key]: '' })).toEqual({})
    })

    it('is omitted when the loaded text is untouched', () => {
      expect(entries({ [key]: '{"a":1}', [loadedKey(key)]: '{"a":1}' })).toEqual([])
    })

    it('is sent once edited', () => {
      expect(entries({ [key]: '{"a":2}', [loadedKey(key)]: '{"a":1}' })).toEqual([['r[details]', { a: 2 }]])
    })
  })

  it('writes the position into the sortable column', () => {
    const section: FormSection = {
      kind: 'has_many',
      name: 'steps',
      param: 'plan[steps_attributes]',
      sortable: 'position',
      fields: [],
      template_fields: [field({ name: 'title', control: 'text', param: 'plan[steps_attributes][__INDEX__][title]' })],
      records: [],
    }
    const rows = { 0: [newRow(section, 5), newRow(section, 6)] }
    const entries = collectEntries([section], rows, { plan__steps_attributes__5__title: 'a', plan__steps_attributes__6__title: 'b' })
    expect(entries).toEqual([
      ['plan[steps_attributes][5][position]', 0],
      ['plan[steps_attributes][5][title]', 'a'],
      ['plan[steps_attributes][6][position]', 1],
      ['plan[steps_attributes][6][title]', 'b'],
    ])
  })
})

describe('mapErrors', () => {
  const fields = activeFields(postForm(posts[0]).form.sections, {})

  it('maps by field name and by the attribute in the param (editor_id)', () => {
    const { byKey, unmatched } = mapErrors({ editor: ['must exist'], published_on: ["can't be blank"] }, [], fields)
    expect(byKey).toEqual({ post__editor_id: 'Must exist', post__published_on: "Can't be blank" })
    expect(unmatched).toEqual([])
    expect(mapErrors({ editor_id: ['must exist'] }, [], fields).byKey).toHaveProperty('post__editor_id')
  })

  it('keeps base errors and humanizes keys with no field', () => {
    const { byKey, unmatched } = mapErrors({ publisher_ref: ['is invalid'] }, ['Could not be saved'], fields)
    expect(byKey).toEqual({})
    expect(unmatched).toEqual(['Could not be saved', 'Publisher ref is invalid'])
  })

  it('maps assoc.attr onto the only matching row, otherwise lists it', () => {
    const { sections } = deskForm(desks[0]).form
    const two = activeFields(sections, initialRows(sections))
    expect(mapErrors({ 'desk_members.user_email': ['is taken'] }, [], two).unmatched).toEqual(['Desk members user email is taken'])

    const single = { ...initialRows(sections) }
    const idx = sections.findIndex((s) => s.kind === 'has_many')
    single[idx] = single[idx].slice(0, 1)
    const one = activeFields(sections, single)
    expect(mapErrors({ 'desk_members.user_email': ['is taken'] }, [], one).byKey).toEqual({ desk__desk_members_attributes__0__user_email: 'Is taken' })
  })
})

describe('compact nested rows', () => {
  const { sections } = deskForm(desks[0]).form
  const at = sections.findIndex((s) => s.kind === 'has_many')
  const section: FormSection = { ...sections[at], layout: 'compact' }

  it('is compact only when the server says so and every row is one simple control', () => {
    expect(isCompact(sections[at])).toBe(false)
    expect(isCompact(section)).toBe(true)
    const withTwo = { ...section, template_fields: [...(section.template_fields ?? []), field({ name: 'note', control: 'text' })] }
    expect(isCompact(withTwo)).toBe(false)
    const multi = { ...section, template_fields: section.template_fields?.map((f) => ({ ...f, multiple: true })) }
    expect(isCompact(multi)).toBe(false)
    const textarea = { ...section, records: [{ id: 'x', fields: [field({ name: 'note', control: 'textarea' })] }] }
    expect(isCompact(textarea)).toBe(false)
  })

  it('makes a new row out of the picked option, which labels it and is what gets sent', () => {
    const row = newRow(section, 4, { label: 'Sarah Chen', value: 'sarah.chen@example.com' })
    const [email] = row.fields
    expect(email).toMatchObject({ value: 'sarah.chen@example.com', options: [{ label: 'Sarah Chen' }], param: 'desk[desk_members_attributes][4][user_email]' })
    const entries = collectEntries([section], { 0: [row] }, defaultValues(activeFields([section], { 0: [row] })))
    expect(entries).toEqual([['desk[desk_members_attributes][4][user_email]', 'sarah.chen@example.com']])
  })

  it('counts what a save will add and remove', () => {
    const rows = initialRows([section])
    const list = [{ ...rows[0][0], removed: true }, rows[0][1], newRow(section, 2), newRow(section, 3)]
    expect(rowChanges({ 0: list })).toEqual({ add: 2, remove: 1 })
    expect(changeSummary({ add: 2, remove: 1 })).toBe('2 to add, 1 to remove')
    expect(changeSummary({ add: 0, remove: 1 })).toBe('1 to remove')
    expect(changeSummary({ add: 0, remove: 0 })).toBe('')
  })

  describe('row errors', () => {
    const rows = initialRows([section])
    const withNew = { 0: [...rows[0], newRow(section, 2), { ...newRow(section, 3), removed: true }, newRow(section, 4)] }
    const named = (rowErrors: Parameters<typeof mapRowErrors>[0]) => mapRowErrors(rowErrors, [section], withNew)

    it('lands a message on the saved row with that id and on the new row by its place among the new ones', () => {
      const { byKey, notes, handled } = named({
        desk_members: [
          { id: 'pu-2', errors: { user_email: ['is already a member of another desk'] } },
          { new: 1, errors: { user: ['must exist'], base: ['is not allowed'] } },
        ],
      })
      expect(byKey).toEqual({ desk__desk_members_attributes__1__user_email: 'Is already a member of another desk' })
      expect(notes).toEqual({ n4: ['User must exist', 'Is not allowed'] })
      expect([...handled]).toEqual(['desk_members'])
    })

    it('ignores a row it cannot find', () => {
      expect(named({ desk_members: [{ id: 'gone', errors: { user_email: ['x'] } }, { new: 9, errors: { user_email: ['x'] } }] })).toMatchObject({ byKey: {}, notes: {} })
    })
  })
})
