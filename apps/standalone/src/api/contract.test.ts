import { readFileSync } from 'node:fs'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { checkResponse, ROUTES, schemaFor, violations } from './contract'

const core = readFileSync(new URL('../../../../openapi/core.yaml', import.meta.url), 'utf8')

describe('contract', () => {
  afterEach(() => {
    violations.splice(0)
    vi.restoreAllMocks()
  })

  it('checks only paths core.yaml declares', () => {
    for (const [, template] of ROUTES) expect(core).toContain(`\n  ${template}:\n`)
  })

  it('matches the most literal template', () => {
    expect(schemaFor('GET', '/admin/posts/new')).toBe('GetNewFormResponse')
    expect(schemaFor('GET', '/admin/posts/7')).toBe('GetRecordResponse')
    expect(schemaFor('GET', '/admin/posts/7/edit')).toBe('GetEditFormResponse')
    expect(schemaFor('POST', '/admin/posts/batch_action')).toBe('RunBatchActionResponse')
    expect(schemaFor('GET', '/admin/authors/1/posts')).toBeUndefined()
  })

  it('reports a response off the contract without its values', () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {})
    checkResponse('GET', '/admin/_session', { user: { id: 'u-1', display_name: 'Dana Whitfield' }, csrf_token: 42 })

    expect(violations).toHaveLength(1)
    expect(violations[0]).toContain('GET /admin/_session')
    expect(violations[0]).toContain('csrf_token')
    expect(violations[0]).not.toContain('Dana')
    expect(error).toHaveBeenCalledOnce()
  })

  it('takes the schema the caller names over the path', () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    checkResponse('GET', '/admin/posts/stats', { options: [], truncated: false }, 'GetOptionsResponse')

    expect(violations).toEqual([])
  })
})
