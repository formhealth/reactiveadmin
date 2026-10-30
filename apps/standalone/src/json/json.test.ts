import { describe, expect, it, vi } from 'vitest'
import { ApiError, isBackgroundRead } from '@/api/fetcher'
import type { FormField } from '@/api/generated/model'
import { submitValue } from '@/forms/model'
import { auditedChanges, isAuditedChanges } from './audit'
import { auditRows, changesBetween } from './diff'
import { blank, describeError, formatText, parseText, toText } from './editor'
import { expandReducer, findFreshPath, isExpandPath, loadFullValue, type Fetcher } from './expand'
import { pathString } from './paths'
import { countMatches, leafCount, moreMarker, paginate, parseMoreMarker, sizeLabel } from './tree'

describe('leafCount', () => {
  it('counts scalars at any depth, not containers', () => {
    expect(leafCount({ a: 1, b: { c: [true, null] } })).toBe(3)
    expect(leafCount([])).toBe(0)
    expect(leafCount('x')).toBe(1)
  })
})

describe('pathString', () => {
  it('joins keys with dots and indexes with brackets', () => {
    expect(pathString(['a', 'b', 0, 'c'])).toBe('a.b[0].c')
    expect(pathString([0, 'a'])).toBe('[0].a')
    expect(pathString([])).toBe('')
  })

  it('quotes keys that are not identifiers', () => {
    expect(pathString(['a', 'x.y', 'z'])).toBe('a["x.y"].z')
    expect(pathString(['1st', 'with space'])).toBe('["1st"]["with space"]')
  })
})

describe('tree helpers', () => {
  it('labels sizes', () => {
    expect(sizeLabel('object', 1)).toBe('1 key')
    expect(sizeLabel('array', 3)).toBe('3 items')
    expect(sizeLabel('scalar', 1)).toBeNull()
  })

  it('counts key and value matches case-insensitively', () => {
    const value = { Status: 'active', plans: [{ status: 'Inactive' }], n: 5 }
    expect(countMatches(value, 'status')).toBe(2)
    expect(countMatches(value, 'inact')).toBe(1)
    expect(countMatches(value, '  ')).toBe(0)
    expect(countMatches(value, '5')).toBe(1)
  })

  it('paginates arrays at any depth and keeps indexes stable', () => {
    const value = { rows: Array.from({ length: 7 }, (_, i) => ({ i })), tags: ['a'] }
    const page = paginate(value, {}, 3) as { rows: unknown[]; tags: unknown[] }
    expect(page.rows.slice(0, 3)).toEqual([{ i: 0 }, { i: 1 }, { i: 2 }])
    expect(page.rows).toHaveLength(4)
    expect(parseMoreMarker(page.rows[3])).toEqual({ path: ['rows'], remaining: 4 })
    expect(page.tags).toEqual(['a'])
    expect(paginate(value, { rows: 6 }, 3)).toMatchObject({ rows: expect.arrayContaining([expect.objectContaining({ i: 5 })]) })
    expect(paginate(value, { rows: 7 }, 3)).toEqual(value)
  })

  it('does not mistake ordinary strings for a marker', () => {
    expect(parseMoreMarker('more')).toBeUndefined()
    expect(parseMoreMarker(moreMarker({ path: [], remaining: 2 }))).toEqual({ path: [], remaining: 2 })
  })
})

describe('summary expansion', () => {
  const path = '/admin/authors/7/_value?field=seo'

  it('accepts only same-origin value endpoints', () => {
    expect(isExpandPath(path)).toBe(true)
    expect(isExpandPath('/api/admin/authors/7/_value?field=a&path=b.c')).toBe(true)
    expect(isExpandPath('/api/admin/authors/7/_value?field=a&token=eyJfcmFpbHMiOnsiZGF0YSI6eyJyIjoicCJ9fQ%3D%3D--0a1b2c3d4e5f')).toBe(true)
    expect(isExpandPath('//evil.example/admin/x/_value')).toBe(false)
    expect(isExpandPath('https://evil.example/admin/x/_value')).toBe(false)
    expect(isExpandPath('/admin/authors/7')).toBe(false)
    expect(isExpandPath(null)).toBe(false)
  })

  it('is never a background read, so the audit sees the view', () => {
    expect(isBackgroundRead(path)).toBe(false)
  })

  it('fetches the path and unwraps the value', async () => {
    const fetcher = vi.fn().mockResolvedValue({ value: { reader_id: '[masked]' } })
    const signal = new AbortController().signal
    await expect(loadFullValue(path, signal, fetcher as unknown as Fetcher)).resolves.toEqual({ reader_id: '[masked]' })
    expect(fetcher).toHaveBeenCalledWith(path, { signal })
  })

  it('refuses an unsafe path without fetching', async () => {
    const fetcher = vi.fn()
    await expect(loadFullValue('//evil.example/_value', undefined, fetcher as unknown as Fetcher)).rejects.toBeInstanceOf(ApiError)
    expect(fetcher).not.toHaveBeenCalled()
  })

  it('moves idle, loading, loaded and back to idle on hide', () => {
    let state = expandReducer({ status: 'idle' }, { type: 'load' })
    expect(state).toEqual({ status: 'loading' })
    state = expandReducer(state, { type: 'loaded', value: { a: 1 } })
    expect(state).toEqual({ status: 'loaded', value: { a: 1 } })
    expect(expandReducer(state, { type: 'hide' })).toEqual({ status: 'idle' })
  })

  it('separates a 403 from other failures', () => {
    const idle = { status: 'idle' } as const
    expect(expandReducer(idle, { type: 'failed', error: new ApiError(403, 'forbidden') })).toEqual({ status: 'error', forbidden: true })
    expect(expandReducer(idle, { type: 'failed', error: new ApiError(500) })).toEqual({ status: 'error', forbidden: false })
    expect(expandReducer(idle, { type: 'failed', error: new Error('network') })).toEqual({ status: 'error', forbidden: false })
  })
})

describe('expired value tokens', () => {
  const stale = '/api/admin/authors/7/_value?field=seo&token=old'
  const fresh = '/api/admin/authors/7/_value?field=seo&token=new'
  const payload = { layout: [{ type: 'group', children: [{ type: 'json', expand_path: '/api/admin/authors/7/_value?field=other&token=x' }, { type: 'json', expand_path: fresh }] }] }
  const forbidden = new ApiError(403, 'forbidden')

  it('finds the same field by everything but the token', () => {
    expect(findFreshPath(payload, stale)).toBe(fresh)
    expect(findFreshPath(payload, '/api/admin/authors/7/_value?field=gone&token=old')).toBeUndefined()
    expect(findFreshPath({ expand_path: stale.replace('&token=old', '') }, stale)).toBe('/api/admin/authors/7/_value?field=seo')
  })

  it('refetches the owner after a 403 and retries once with the fresh path', async () => {
    const fetcher = vi.fn().mockRejectedValueOnce(forbidden).mockResolvedValueOnce({ value: { ok: 1 } })
    const refresh = vi.fn().mockResolvedValue(payload)
    await expect(loadFullValue(stale, undefined, fetcher as unknown as Fetcher, refresh)).resolves.toEqual({ ok: 1 })
    expect(refresh).toHaveBeenCalledOnce()
    expect(fetcher.mock.calls.map(([url]) => url)).toEqual([stale, fresh])
  })

  it('stays forbidden when the retry is refused too', async () => {
    const fetcher = vi.fn().mockRejectedValue(forbidden)
    const refresh = vi.fn().mockResolvedValue(payload)
    await expect(loadFullValue(stale, undefined, fetcher as unknown as Fetcher, refresh)).rejects.toBe(forbidden)
    expect(fetcher).toHaveBeenCalledTimes(2)
  })

  it('does not retry when the refreshed path is unchanged or missing', async () => {
    const fetcher = vi.fn().mockRejectedValue(forbidden)
    await expect(loadFullValue(stale, undefined, fetcher as unknown as Fetcher, async () => ({ expand_path: stale }))).rejects.toBe(forbidden)
    await expect(loadFullValue(stale, undefined, fetcher as unknown as Fetcher, async () => ({}))).rejects.toBe(forbidden)
    expect(fetcher).toHaveBeenCalledTimes(2)
  })

  it('ignores other errors and pages with no owner to refresh', async () => {
    const refresh = vi.fn()
    const failing = vi.fn().mockRejectedValue(new ApiError(500))
    await expect(loadFullValue(stale, undefined, failing as unknown as Fetcher, refresh)).rejects.toBeInstanceOf(ApiError)
    expect(refresh).not.toHaveBeenCalled()
    const denied = vi.fn().mockRejectedValue(forbidden)
    await expect(loadFullValue(stale, undefined, denied as unknown as Fetcher)).rejects.toBe(forbidden)
    expect(denied).toHaveBeenCalledOnce()
  })
})

describe('diff', () => {
  const changes = { status: ['pending', 'published'], embargo_until: [null, '2026-11-01'], details: [{ a: 1, b: [1, 2] }, { a: 2, b: [1, 2, 3] }] }

  it('detects the audited shape strictly', () => {
    expect(isAuditedChanges(changes)).toBe(true)
    expect(isAuditedChanges({})).toBe(false)
    expect(isAuditedChanges({ a: [1, 2, 3] })).toBe(false)
    expect(isAuditedChanges({ a: 'x', b: [1, 2] })).toBe(false)
    expect(isAuditedChanges([[1, 2]])).toBe(false)
  })

  it('needs a reason beyond the shape before treating a node as an audit', () => {
    expect(auditedChanges({ value: changes }, {})).toBeUndefined()
    expect(auditedChanges({ value: changes }, { resource: 'audits' })).toBe(changes)
    expect(auditedChanges({ value: changes }, { label: 'Audited changes' })).toBe(changes)
    expect(auditedChanges({ value: changes, diff: true } as never, {})).toBe(changes)
    expect(auditedChanges({ value: { a: [1, 2, 3] }, diff: true } as never, {})).toBeUndefined()
  })

  it('walks leaf changes with paths', () => {
    expect(changesBetween({ a: 1, b: { c: 'x' }, d: [1, 2] }, { a: 2, b: { c: 'x', e: true }, d: [1] })).toEqual([
      { path: 'a', op: 'modified', before: 1, after: 2 },
      { path: 'b.e', op: 'added', after: true },
      { path: 'd[1]', op: 'removed', before: 2 },
    ])
    expect(changesBetween({ a: 1 }, { a: 1 })).toEqual([])
  })

  it('flattens audited fields, expanding structured ones to their leaves', () => {
    expect(auditRows(changes as never)).toEqual([
      { path: 'status', op: 'modified', before: 'pending', after: 'published' },
      { path: 'embargo_until', op: 'added', before: null, after: '2026-11-01' },
      { path: 'details.a', op: 'modified', before: 1, after: 2 },
      { path: 'details.b[2]', op: 'added', after: 3 },
    ])
  })
})

describe('editor text', () => {
  const field = { control: 'json' } as FormField

  it('treats blank text as null and valid text as its value', () => {
    expect(blank(' \n')).toBe(true)
    expect(parseText('')).toEqual({ ok: true, value: null })
    expect(parseText('{"a":[1,2]}')).toEqual({ ok: true, value: { a: [1, 2] } })
  })

  it('reports invalid text with the token and its line and column, without echoing the document', () => {
    const parsed = parseText('{\n  "a": 1,\n  "b": }')
    expect(parsed).toEqual({ ok: false, error: expect.stringMatching(/^Unexpected token '\}'.* \(line 3, column 8\)$/) })
    if (!parsed.ok) expect(parsed.error).not.toContain('"a"')
    expect(parseText('{"a": 1,}').ok).toBe(false)
  })

  it('drops the echoed snippet in either engine wording', () => {
    const text = '{"a": }'
    const chrome = new Error(`Unexpected token '}', ..."{"a": }" is not valid JSON`)
    const node = new Error(`Unexpected token '}', "{"a": }" is not valid JSON`)
    expect(describeError(text, chrome)).toBe("Unexpected token '}' (line 1, column 7)")
    expect(describeError(text, node)).toBe("Unexpected token '}' (line 1, column 7)")
    expect(describeError('{', new Error("Expected property name or '}' in JSON at position 1 (line 1 column 2)"))).toBe("Expected property name or '}' (line 1, column 2)")
  })

  it('locates incomplete text at its end', () => {
    expect(describeError('{"a": [1, 2', new Error('Unexpected end of JSON input'))).toBe('Unexpected end of JSON input (line 1, column 12)')
  })

  it('formats without reordering keys and leaves invalid text alone', () => {
    expect(formatText('{"z":1,"a":{"y":2,"b":3}}')).toBe('{\n  "z": 1,\n  "a": {\n    "y": 2,\n    "b": 3\n  }\n}')
    expect(formatText('{"a":')).toBe('{"a":')
    expect(formatText('')).toBe('')
  })

  it('round-trips through the form submit format as a value, not a string', () => {
    const text = toText({ b: 1, a: [true, null] })
    expect(submitValue(field, text)).toEqual({ b: 1, a: [true, null] })
    expect(Object.keys(submitValue(field, text) as object)).toEqual(['b', 'a'])
    expect(submitValue(field, '')).toBeNull()
  })
})
