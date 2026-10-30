import { create, type Delta } from 'jsondiffpatch'
import type { AuditedChange } from './audit'
import { pathString, type PathKey } from './paths'

export type ChangeOp = 'added' | 'removed' | 'modified'

export type Change = { path: string; op: ChangeOp; before?: unknown; after?: unknown }

const differ = create({ arrays: { detectMove: false } })

const isArrayDelta = (delta: object) => '_t' in delta && delta._t === 'a'

// jsondiffpatch encodes a leaf as [new], [old, new] or [old, 0, 0]; objects and arrays nest.
function walk(delta: NonNullable<Delta>, path: PathKey[], out: Change[]) {
  const here = pathString(path)
  if (Array.isArray(delta)) {
    if (delta.length === 1) out.push({ path: here, op: 'added', after: delta[0] })
    else if (delta[2] === 0) out.push({ path: here, op: 'removed', before: delta[0] })
    else out.push({ path: here, op: 'modified', before: delta[0], after: delta[1] })
    return
  }
  const array = isArrayDelta(delta)
  for (const [key, child] of Object.entries(delta)) {
    if (key === '_t') continue
    // Array deltas key removals as `_<oldIndex>` and the rest by new index.
    const removed = array && key.startsWith('_')
    const step = array ? Number(removed ? key.slice(1) : key) : key
    walk(child as NonNullable<Delta>, [...path, step], out)
  }
}

// Leaf-level differences between two JSON values, with paths in `a.b[0]` form relative to the root.
export function changesBetween(before: unknown, after: unknown, base: PathKey[] = []): Change[] {
  const delta = differ.diff(before, after)
  const out: Change[] = []
  if (delta) walk(delta, base, out)
  return out
}

const structured = (v: unknown) => typeof v === 'object' && v !== null

// One row per changed field; fields holding objects or arrays on both sides expand to their changed leaves.
export function auditRows(changes: Record<string, AuditedChange>): Change[] {
  return Object.entries(changes).flatMap(([field, [before, after]]): Change[] => {
    if (structured(before) && structured(after)) {
      const leaves = changesBetween(before, after, [field])
      if (leaves.length) return leaves
    }
    const op: ChangeOp = before == null ? 'added' : after == null ? 'removed' : 'modified'
    return [{ path: pathString([field]), op, before, after }]
  })
}
