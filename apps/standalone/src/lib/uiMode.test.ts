import { describe, expect, it } from 'vitest'
import { appliesDefault, readUiChoice, storeUiChoice, switchUi, withoutClassic } from './uiMode'

describe('readUiChoice', () => {
  it('reads the two choices among other cookies', () => {
    expect(readUiChoice('a=1; reactiveadmin_ui=new; b=2')).toBe('new')
    expect(readUiChoice('reactiveadmin_ui=classic')).toBe('classic')
  })

  it('has none for a missing, empty or unknown value', () => {
    expect([readUiChoice(''), readUiChoice('reactiveadmin_ui='), readUiChoice('reactiveadmin_ui=beta'), readUiChoice('x_reactiveadmin_ui=new')]).toEqual([
      undefined,
      undefined,
      undefined,
      undefined,
    ])
  })
})

describe('storeUiChoice', () => {
  const store = (choice: Parameters<typeof storeUiChoice>[0], secure = false) => {
    const jar = { cookie: '' }
    storeUiChoice(choice, jar, secure)
    return jar.cookie
  }

  it('sets a year-long, root-path, same-site cookie', () => {
    expect(store('new')).toBe('reactiveadmin_ui=new; path=/; SameSite=Lax; max-age=31536000')
    expect(store('classic')).toBe('reactiveadmin_ui=classic; path=/; SameSite=Lax; max-age=31536000')
  })

  it('is secure over https', () => {
    expect(store('new', true)).toMatch(/; Secure$/)
  })

  it('clears the cookie when there is no choice', () => {
    expect(store(undefined)).toBe('reactiveadmin_ui=; path=/; SameSite=Lax; max-age=0')
  })
})

describe('withoutClassic', () => {
  it('drops the escape hatch and keeps the rest', () => {
    expect(withoutClassic('https://a.test/admin/posts?page=2&classic=1#top')).toBe('https://a.test/admin/posts?page=2#top')
    expect(withoutClassic('https://a.test/admin?classic=1')).toBe('https://a.test/admin')
    expect(withoutClassic('https://a.test/admin/posts')).toBe('https://a.test/admin/posts')
  })
})

describe('switchUi', () => {
  it('stores the choice and loads the same page', () => {
    const jar = { cookie: '' }
    const loaded: string[] = []

    switchUi('new', { href: 'https://a.test/admin/posts?classic=1', assign: (url) => void loaded.push(String(url)) }, jar)

    expect(jar.cookie).toMatch(/^reactiveadmin_ui=new;/)
    expect(loaded).toEqual(['https://a.test/admin/posts'])
  })

  it('loads the given page instead for one only the client has', () => {
    const loaded: string[] = []

    switchUi('classic', { href: 'https://a.test/admin/groups/setup', assign: (url) => void loaded.push(String(url)) }, { cookie: '' }, '/admin')

    expect(loaded).toEqual(['/admin'])
  })

  it('stays put when the browser refuses the cookie, rather than reloading in a loop', () => {
    const loaded: string[] = []
    const blocked = Object.defineProperty({}, 'cookie', { get: () => '', set: () => {} }) as { cookie: string }

    switchUi('new', { href: 'https://a.test/admin', assign: (url) => void loaded.push(String(url)) }, blocked)

    expect(loaded).toEqual([])
  })
})

describe('appliesDefault', () => {
  it('applies a default of new to a browser with no choice', () => {
    expect(appliesDefault('new', '', '')).toBe(true)
    expect(appliesDefault('new', 'other=1', '?page=2')).toBe(true)
  })

  it('leaves a choice, a classic default and a one-off classic page alone', () => {
    expect(appliesDefault('new', 'reactiveadmin_ui=classic', '')).toBe(false)
    expect(appliesDefault('new', 'reactiveadmin_ui=new', '')).toBe(false)
    expect(appliesDefault('classic', '', '')).toBe(false)
    expect(appliesDefault(undefined, '', '')).toBe(false)
    expect(appliesDefault('new', '', '?classic=1')).toBe(false)
  })
})
