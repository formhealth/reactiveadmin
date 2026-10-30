import { describe, expect, it } from 'vitest'
import { readConfig } from './base'

const page = (content?: string) => ({ querySelector: () => (content === undefined ? null : ({ content } as HTMLMetaElement)) }) as unknown as Pick<Document, 'querySelector'>
const shell = (admin_path: unknown, mount_path: unknown = '/api') => page(JSON.stringify({ admin_path, mount_path }))

describe('readConfig', () => {
  it('puts the router at the root and classic at /admin without the shell, as in dev', () => {
    expect(readConfig(page(), {})).toEqual({ adminPath: '/admin', hosted: false, routerBase: '', mountPath: '/api' })
    expect(readConfig(undefined, {})).toEqual({ adminPath: '/admin', hosted: false, routerBase: '', mountPath: '/api' })
  })

  it('lets dev move the router and the classic path', () => {
    expect(readConfig(page(), { VITE_ROUTER_BASE: '/new/', VITE_ADMIN_PATH: '/ops' })).toEqual({ adminPath: '/ops', hosted: false, routerBase: '/new', mountPath: '/api' })
  })

  it("puts the router at the classic admin's own path when the Rails shell says where it is", () => {
    expect(readConfig(shell('/admin', '/api'), {})).toEqual({ adminPath: '/admin', hosted: true, routerBase: '/admin', mountPath: '/api' })
    expect(readConfig(shell('/staff/', '/internal-api/'), { VITE_ROUTER_BASE: '/ignored' })).toEqual({ adminPath: '/staff', hosted: true, routerBase: '/staff', mountPath: '/internal-api' })
  })

  it('takes nothing but plain paths from the page', () => {
    const config = readConfig(shell('https://evil.example/admin', '//evil.example'), {})

    expect(config).toEqual({ adminPath: '/admin', hosted: true, routerBase: '/admin', mountPath: '/api' })
    expect(readConfig(shell({ x: 1 }, 7), {}).adminPath).toBe('/admin')
    expect(readConfig(page('not json'), {})).toEqual({ adminPath: '/admin', hosted: false, routerBase: '', mountPath: '/api' })
  })
})
