export type ScreenKind = 'home' | 'group' | 'page' | 'index' | 'show' | 'new' | 'edit'
export const SCREEN_KINDS: ScreenKind[] = ['home', 'group', 'page', 'index', 'show', 'new', 'edit']

export type Screen = { id: string; kind: ScreenKind; resource?: string; path: string }
export type Skipped = { id: string; reason: string }

type MenuNode = { id: string; kind?: string; resource?: string | null; page?: string | null; children: MenuNode[] }
export type ManifestLike = {
  menu: MenuNode[]
  resources: { key: string; actions: string[]; belongs_to?: { optional?: boolean } }[]
}

export type PlanOptions = { resources?: string[]; kinds: ScreenKind[]; limit: number }

const encode = encodeURIComponent
const leaves = (items: MenuNode[]): MenuNode[] => items.flatMap((item) => (item.children.length ? leaves(item.children) : [item]))
const groups = (items: MenuNode[]): MenuNode[] => items.flatMap((item) => (item.children.length ? [item, ...groups(item.children)] : []))

// Resources a menu item reaches that the manifest leaves out because an `api` guard denies them; they still render a notice.
const denied = (manifest: ManifestLike) => {
  const known = new Set(manifest.resources.map((r) => r.key))
  return leaves(manifest.menu).flatMap((item) => (item.resource && !known.has(item.resource) ? [item.resource] : []))
}

export const needsRecords = (kinds: ScreenKind[]) => kinds.includes('show') || kinds.includes('edit')

// A resource nested under a required parent has no top-level routes, so only its parent's screens reach it.
const nestedUnderRequired = (r: ManifestLike['resources'][number]) => r.belongs_to !== undefined && !r.belongs_to.optional

export function planResourceKeys(manifest: ManifestLike, { resources }: Pick<PlanOptions, 'resources'>) {
  return manifest.resources.filter((r) => !nestedUnderRequired(r) && (!resources || resources.includes(r.key))).map((r) => r.key)
}

export function buildPlan(manifest: ManifestLike, idsByResource: Record<string, string[]>, { resources, kinds, limit }: PlanOptions) {
  const screens: Screen[] = []
  const skipped: Skipped[] = []
  const add = (screen: Screen) => kinds.includes(screen.kind) && screens.push(screen)

  if (!resources) {
    add({ id: 'home', kind: 'home', path: '/' })
    groups(manifest.menu).forEach((g) => add({ id: `group:${g.id}`, kind: 'group', path: `/groups/${g.id}` }))
    leaves(manifest.menu).forEach((item) => item.page && add({ id: `page:${item.page}`, kind: 'page', path: `/${encode(item.page)}` }))
  }

  for (const key of denied(manifest).filter((key) => !resources || resources.includes(key))) add({ id: `index:${key}`, kind: 'index', resource: key, path: `/${encode(key)}` })

  for (const r of manifest.resources.filter((r) => !resources || resources.includes(r.key))) {
    if (nestedUnderRequired(r)) {
      skipped.push({ id: r.key, reason: 'nested under a required parent' })
      continue
    }
    const base = `/${encode(r.key)}`
    add({ id: `index:${r.key}`, kind: 'index', resource: r.key, path: base })
    const ids = (idsByResource[r.key] ?? []).slice(0, limit)
    if (r.actions.includes('show')) ids.forEach((id) => add({ id: `show:${r.key}:${id}`, kind: 'show', resource: r.key, path: `${base}/${encode(id)}` }))
    if (r.actions.includes('new')) add({ id: `new:${r.key}`, kind: 'new', resource: r.key, path: `${base}/new` })
    if (r.actions.includes('edit') && ids[0] !== undefined) add({ id: `edit:${r.key}:${ids[0]}`, kind: 'edit', resource: r.key, path: `${base}/${encode(ids[0])}/edit` })
  }
  return { screens, skipped }
}
