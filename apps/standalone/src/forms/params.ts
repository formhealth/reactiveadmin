export type Entry = [param: string, value: unknown]

type Tree = Record<string, unknown>

const segments = (param: string) => [...param.matchAll(/^[^[\]]+|\[([^[\]]*)\]/g)].map((m) => m[1] ?? m[0]).filter(Boolean)

// `a[b][0][c]` -> { a: { b: { 0: { c } } } }. Rails nested attributes take index-keyed hashes, so numeric
// segments stay object keys. A trailing `[]` marks an array value.
export function paramsToObject(entries: Entry[]): Tree {
  const root: Tree = {}
  for (const [param, value] of entries) {
    const path = segments(param)
    const last = path.pop()
    if (!last) continue
    const parent = path.reduce<Tree>((node, key) => {
      if (typeof node[key] !== 'object' || node[key] === null) node[key] = {}
      return node[key] as Tree
    }, root)
    parent[last] = param.endsWith('[]') ? [...((parent[last] as unknown[]) ?? []), ...[value].flat()] : value
  }
  return root
}

const isFile = (value: unknown): value is File => typeof File !== 'undefined' && value instanceof File

export const hasFile = (entries: Entry[]) => entries.some(([, value]) => isFile(value))

// Rails parses bracketed names natively, so entries are appended as-is; structured values go as JSON strings.
export function toFormData(entries: Entry[]) {
  const data = new FormData()
  for (const [param, value] of entries) {
    for (const item of param.endsWith('[]') ? [value].flat() : [value]) {
      if (item === undefined) continue
      const plain = item !== null && typeof item === 'object' && !isFile(item) ? JSON.stringify(item) : (item ?? '')
      data.append(param, isFile(plain) ? plain : String(plain))
    }
  }
  return data
}
