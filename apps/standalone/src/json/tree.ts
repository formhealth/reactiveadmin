import { pathString, type PathKey } from './paths'

export const MASKED = '[masked]'
export const PAGE_SIZE = 50

export type JsonKind = 'object' | 'array' | 'scalar'

export const isPlainObject = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)

export const kindOf = (value: unknown): JsonKind => (Array.isArray(value) ? 'array' : isPlainObject(value) ? 'object' : 'scalar')

export const sizeOf = (value: unknown) => (Array.isArray(value) ? value.length : isPlainObject(value) ? Object.keys(value).length : 1)

// Scalars at any depth, so a nested object of a few values still counts as small.
export const leafCount = (value: unknown): number =>
  Array.isArray(value) ? value.reduce<number>((n, item) => n + leafCount(item), 0) : isPlainObject(value) ? Object.values(value).reduce<number>((n, item) => n + leafCount(item), 0) : 1

// "3 keys", "1 item"; null for scalars.
export function sizeLabel(kind: JsonKind, size: number) {
  if (kind === 'scalar') return null
  const unit = kind === 'object' ? 'key' : 'item'
  return `${size} ${unit}${size === 1 ? '' : 's'}`
}

const hit = (text: unknown, term: string) => String(text).toLowerCase().includes(term)

// Mirrors the viewer's key-or-value matching so the count agrees with what is highlighted.
export function countMatches(value: unknown, term: string): number {
  const t = term.trim().toLowerCase()
  if (!t) return 0
  const walk = (node: unknown, key?: PathKey): number => {
    const own = typeof key === 'string' && hit(key, t) ? 1 : 0
    if (Array.isArray(node)) return own + node.reduce<number>((n, item, i) => n + walk(item, i), 0)
    if (isPlainObject(node)) return own + Object.entries(node).reduce((n, [k, v]) => n + walk(v, k), 0)
    return own + (node !== null && node !== undefined && hit(node, t) ? 1 : 0)
  }
  return walk(value)
}

const MORE = '\u0000more:'

export type MoreMarker = { path: PathKey[]; remaining: number }

export const moreMarker = (marker: MoreMarker) => `${MORE}${JSON.stringify(marker)}`

export function parseMoreMarker(value: unknown): MoreMarker | undefined {
  if (typeof value !== 'string' || !value.startsWith(MORE)) return undefined
  try {
    return JSON.parse(value.slice(MORE.length))
  } catch {
    return undefined
  }
}

export type Limits = Record<string, number>

// Arrays past their limit are cut and end in a marker item. Kept items retain their indexes, so paths
// reported by the viewer are valid against the original value.
export function paginate(value: unknown, limits: Limits = {}, pageSize = PAGE_SIZE): unknown {
  const walk = (node: unknown, path: PathKey[]): unknown => {
    if (Array.isArray(node)) {
      const limit = limits[pathString(path)] ?? pageSize
      const shown = node.slice(0, limit).map((item, i) => walk(item, [...path, i]))
      return node.length > limit ? [...shown, moreMarker({ path, remaining: node.length - limit })] : shown
    }
    if (isPlainObject(node)) return Object.fromEntries(Object.entries(node).map(([k, v]) => [k, walk(v, [...path, k])]))
    return node
  }
  return walk(value, [])
}
