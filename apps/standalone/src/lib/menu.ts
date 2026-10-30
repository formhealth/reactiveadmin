import type { MenuItem } from '@/api/generated/model'

export type MenuLeaf = {
  id: string
  label: string
  path: string[]
  description?: string | null
  resource?: string | null
  page?: string | null
  url?: string | null
  api_denied?: boolean
}

// Older servers omit `kind`; an item with children is a group.
export const isGroup = (item: Pick<MenuItem, 'kind' | 'children'>) => item.kind === 'group' || item.children.length > 0

export const groupRoute = (id: string) => `/groups/${id}`

export const fullPath = ({ path, label }: Pick<MenuLeaf, 'path' | 'label'>) => [...path, label].join(' / ')

const goesSomewhere = (item: MenuItem) => item.resource || item.page || item.url

// Drops leaves that go nowhere and groups left empty.
export const pruneMenu = (items: MenuItem[]): MenuItem[] =>
  items.flatMap((item) => {
    if (item.children.length === 0) return goesSomewhere(item) ? [item] : []
    const children = pruneMenu(item.children)
    return children.length ? [{ ...item, children }] : []
  })

const entry = (item: MenuItem, path: string[]): MenuLeaf => ({
  id: item.id,
  label: item.label,
  path,
  description: item.description,
  resource: item.resource,
  page: item.page,
  url: item.url,
  api_denied: item.api_denied,
})

const walk = (items: MenuItem[], path: string[]): MenuLeaf[] =>
  items.flatMap((item) => (item.children.length ? walk(item.children, [...path, item.label]) : [entry(item, path)]))

export const menuLeaves = (items: MenuItem[]) => walk(pruneMenu(items), [])

const walkGroups = (items: MenuItem[], path: string[]): MenuLeaf[] =>
  items.flatMap((item) => (item.children.length ? [entry(item, path), ...walkGroups(item.children, [...path, item.label])] : []))

// Every group, with the path above it; each has an overview page.
export const menuGroups = (items: MenuItem[]) => walkGroups(pruneMenu(items), [])

export const findGroup = (items: MenuItem[], id: string): { group: MenuItem; path: MenuItem[] } | undefined => {
  for (const item of items) {
    if (item.id === id && item.children.length) return { group: item, path: [] }
    const found = findGroup(item.children, id)
    if (found) return { group: found.group, path: [item, ...found.path] }
  }
}

// Matches on the full path, so "billing plans" finds "Setup / Billing / Billing plans". Results are flat.
export function searchMenu(items: MenuItem[], term: string): { leaves: MenuLeaf[]; groups: MenuLeaf[] } {
  const words = term.toLowerCase().split(/\s+/).filter(Boolean)
  const matches = (entry: MenuLeaf) => {
    const haystack = `${fullPath(entry)} ${entry.description ?? ''}`.toLowerCase()
    return words.every((word) => haystack.includes(word))
  }
  return { leaves: menuLeaves(items).filter(matches), groups: menuGroups(items).filter(matches) }
}

export type Here = { resource?: string; page?: string; group?: string }

// Where the router is: `/groups/<group id>` is an overview; anything else starts with a resource key or a page's, the
// way classic URLs do (`/admin/posts`, `/admin/dashboard`).
export const hereOf = (pathname: string): Here => {
  const [first, ...rest] = pathname.split('/').filter(Boolean)
  return first === 'groups' ? { group: rest.join('/') } : { resource: first, page: first }
}

// Ids from the root group down to the item for the current resource or page, or [] when it isn't in the menu.
export function trailTo(items: MenuItem[], here: Here): string[] {
  for (const item of items) {
    if ((item.resource && item.resource === here.resource) || (item.page && item.page === here.page) || (here.group && item.children.length > 0 && item.id === here.group)) return [item.id]
    const rest = trailTo(item.children, here)
    if (rest.length) return [item.id, ...rest]
  }
  return []
}

// In-app route of a menu leaf; undefined when it only has a classic URL the client can't map.
// A classic-only item is the classic page itself, not a route the client could serve.
export const menuRoute = (leaf: Pick<MenuItem, 'resource' | 'page' | 'url' | 'api_denied'>, mapUrl: (url: string) => string | undefined) =>
  leaf.api_denied ? undefined : leaf.resource ? `/${leaf.resource}` : leaf.page ? `/${leaf.page}` : leaf.url ? mapUrl(leaf.url) : undefined
