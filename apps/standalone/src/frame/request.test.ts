import { describe, expect, it } from 'vitest'
import { buildFrameRequest, buildLinkRequest, classicLink, filenameOf, sameTitle } from './request'

const from = 'https://app.test/authors/9/actions/team_history'

const form = (entries: Record<string, string | File>) => {
  const data = new FormData()
  for (const [key, value] of Object.entries(entries)) data.append(key, value)
  return data
}

const bodyOf = (body: BodyInit | null | undefined) => Object.fromEntries(new URLSearchParams(String(body)))
const header = (request: { init: RequestInit }, name: string) => (request.init.headers as Record<string, string>)[name]

describe('buildFrameRequest', () => {
  it('posts urlencoded, keeps _method and the submitter, and drops the CSRF field', () => {
    const request = buildFrameRequest({
      action: '/admin/team_members/7',
      method: 'post',
      data: form({ authenticity_token: 'secret', _method: 'patch', utf8: '✓', 'member[role]': 'copy editor', commit: 'Save' }),
      base: from,
    })!
    expect(request.url).toBe('/admin/team_members/7')
    expect(request.init.method).toBe('POST')
    expect(bodyOf(request.init.body)).toEqual({ _method: 'patch', utf8: '✓', 'member[role]': 'copy editor', commit: 'Save' })
    expect(header(request, 'Content-Type')).toMatch(/x-www-form-urlencoded/)
    expect(header(request, 'X-Reactiveadmin-Frame')).toBe('1')
    expect(JSON.stringify(request.init.headers)).not.toMatch(/csrf/i)
  })

  it('posts a form that names another verb with that verb as _method', () => {
    const request = buildFrameRequest({ action: '/admin/team_members/7', method: 'patch', data: form({ 'member[role]': 'md' }), base: from })!
    expect(request.init.method).toBe('POST')
    expect(bodyOf(request.init.body)).toEqual({ 'member[role]': 'md', _method: 'patch' })
    const kept = buildFrameRequest({ action: '/admin/x/1', method: 'delete', data: form({ _method: 'delete' }), base: from })!
    expect(bodyOf(kept.init.body)).toEqual({ _method: 'delete' })
  })

  it('sends multipart as FormData without a content type', () => {
    const file = new File(['x'], 'scan.pdf')
    const request = buildFrameRequest({ action: '/admin/uploads', method: 'POST', enctype: 'multipart/form-data', data: form({ authenticity_token: 't', 'upload[file]': file }), base: from })!
    const body = request.init.body as FormData
    expect(body).toBeInstanceOf(FormData)
    expect(body.get('upload[file]')).toBeInstanceOf(File)
    expect(body.has('authenticity_token')).toBe(false)
    expect(header(request, 'Content-Type')).toBeUndefined()
  })

  it('turns GET forms into a query that replaces the action query', () => {
    const request = buildFrameRequest({ action: '/admin/authors/9/team_history?old=1', method: 'get', data: form({ 'q[role]': 'md', commit: 'Filter' }), base: from })!
    expect(request.init.method).toBe('GET')
    expect(request.init.body).toBeUndefined()
    expect(request.url).toBe('/admin/authors/9/team_history?q%5Brole%5D=md&commit=Filter')
  })

  it('defaults to the frame URL and refuses other origins', () => {
    expect(buildFrameRequest({ action: '', method: 'get', data: form({}), base: from })?.url).toBe('/authors/9/actions/team_history')
    expect(buildFrameRequest({ action: 'https://evil.test/admin', method: 'post', data: form({}), base: from })).toBeUndefined()
  })
})

describe('buildLinkRequest', () => {
  it('emulates rails-ujs data-method links', () => {
    const request = buildLinkRequest('/admin/team_members/7', 'delete', from)!
    expect(request.init.method).toBe('POST')
    expect(bodyOf(request.init.body)).toEqual({ _method: 'delete' })
    expect(buildLinkRequest('/admin/x/run', 'post', from)!.init.body?.toString()).toBe('')
    expect(buildLinkRequest('/admin/x', 'get', from)!.init.method).toBe('GET')
    expect(buildLinkRequest('https://evil.test/x', 'delete', from)).toBeUndefined()
  })
})

describe('classicLink', () => {
  it('drops the embed flag but keeps the rest', () => {
    expect(classicLink('/admin/authors/9/preview_schedule?embed=1', from)).toBe('/admin/authors/9/preview_schedule?classic=1')
    expect(classicLink('/admin/x?a=1&embed=1&b=2', from)).toBe('/admin/x?a=1&b=2&classic=1')
  })
})

describe('filenameOf', () => {
  it('reads attachment names', () => {
    expect(filenameOf('attachment; filename="team.csv"')).toBe('team.csv')
    expect(filenameOf("attachment; filename*=UTF-8''team%20roster.csv")).toBe('team roster.csv')
    expect(filenameOf(null)).toBeUndefined()
  })
})

describe('sameTitle', () => {
  it('matches a repeated page heading however it is cased or punctuated', () => {
    expect(sameTitle('  Team history ', 'Team History')).toBe(true)
    expect(sameTitle('Team: history', 'Team history')).toBe(true)
    expect(sameTitle('Team members', 'Team history')).toBe(false)
    expect(sameTitle('Anything', undefined)).toBe(false)
  })
})
