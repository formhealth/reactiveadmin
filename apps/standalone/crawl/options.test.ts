import { describe, expect, it } from 'vitest'
import { parseOptions, type Options } from './options.ts'

const parse = (...argv: string[]) => parseOptions(argv, {}) as Options

describe('parseOptions', () => {
  it('takes a host that serves the client at its admin path', () => {
    const options = parse('--base-url=https://host.example/admin/')
    expect(options).toMatchObject({ baseUrl: 'https://host.example/admin', origin: 'https://host.example', classicPath: '/admin' })
  })

  it('defaults the classic path to /admin for a bare origin and takes an override', () => {
    expect(parse('--base-url=http://localhost:5174').classicPath).toBe('/admin')
    expect(parse('--base-url=https://host.example/staff', '--classic-path=/admin').classicPath).toBe('/admin')
    expect(parse('--base-url=https://host.example/staff').classicPath).toBe('/staff')
  })

  it('reads --auth as the login hook', () => {
    expect(parse('--auth=hook.ts').login).toMatch(/hook\.ts$/)
  })

  it('collects repeated budgets and enables parity', () => {
    const options = parse('--budget=p95=1500', '--budget', 'index.max=4000', '--parity')
    expect(options.budgets).toEqual({ all: { p95: 1500 }, index: { max: 4000 } })
    expect(options.parity).toBe(true)
    expect(parse().parity).toBe(false)
  })

  it('rejects a bad budget', () => {
    expect(() => parse('--budget=p95')).toThrow('--budget')
  })
})
