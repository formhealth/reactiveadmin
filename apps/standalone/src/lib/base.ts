type Injected = { admin_path?: unknown; mount_path?: unknown }

const trim = (path: string) => path.replace(/\/+$/, '')
const asPath = (value: unknown) => (typeof value === 'string' && /^\/(?!\/)(?!.*\.\.)[\w\-./]*$/.test(value) ? trim(value) : undefined)

// Where the client lives. `hosted` is a Rails shell serving it. Loaded by the Rails shell, the page says so in `<meta name="reactiveadmin-config">`, and the
// router then sits at the classic admin's own path: a client URL and its classic URL are the same string. In dev
// (or against mocks) there is no tag: the router is at the root and the classic admin is `/admin/...`; VITE_ROUTER_BASE
// and VITE_ADMIN_PATH change that.
export function readConfig(doc?: Pick<Document, 'querySelector'>, env: Record<string, string | undefined> = import.meta.env) {
  const raw = doc?.querySelector<HTMLMetaElement>('meta[name="reactiveadmin-config"]')?.content
  let injected: Injected | undefined
  try {
    injected = raw ? JSON.parse(raw) : undefined
  } catch {
    injected = undefined
  }
  const adminPath = asPath(injected?.admin_path) ?? asPath(env.VITE_ADMIN_PATH) ?? '/admin'
  return {
    adminPath,
    hosted: !!injected,
    routerBase: injected ? adminPath : (asPath(env.VITE_ROUTER_BASE) ?? ''),
    mountPath: asPath(injected?.mount_path) ?? '/api',
  }
}

export const { adminPath, hosted, routerBase, mountPath } = readConfig(globalThis.document)
