import { describe, expect, it } from 'vitest'
import { safeMediaSrc } from './safeMedia'

const from = 'https://admin.test/admin/attachments/1'
const hosts = ['cdn.example.test']

describe('safeMediaSrc', () => {
  it.each(['/files/a.png', 'https://admin.test/files/a.png', 'https://cdn.example.test/abc/?token=x', 'HTTPS://CDN.EXAMPLE.TEST/abc/'])('keeps %s', (src) => {
    expect(safeMediaSrc(src, hosts, from)).toBe(src)
  })

  it.each([
    'https://evil.example/a.png',
    'https://cdn.example.test.evil.example/a.png',
    'https://cdn.example.test@evil.example/a.png',
    'https://user:pass@cdn.example.test/a.png',
    '//cdn.example.test/a.png',
    'data:image/png;base64,iVBORw0KGgo=',
    'data:application/pdf;base64,AA==',
    'javascript:alert(1)',
    'JaVaScRiPt:alert(1)',
    'blob:https://admin.test/x',
    'ftp://cdn.example.test/a.png',
    'https:cdn.example.test/a.png',
    'a.png',
    ' /files/a.png',
    '/files/a b.png',
    '/\\evil.example/a.png',
    '',
    undefined,
    null,
  ])('rejects %s', (src) => {
    expect(safeMediaSrc(src, hosts, from)).toBeUndefined()
  })

  it('trusts no other host until the manifest names one', () => {
    expect(safeMediaSrc('https://cdn.example.test/abc/', [], from)).toBeUndefined()
  })
})
