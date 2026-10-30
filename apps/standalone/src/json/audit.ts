import { isPlainObject } from './tree'

export type AuditedChange = [before: unknown, after: unknown]

// Audits store `{ field: [old, new] }`. A lone `{ tags: ["a", "b"] }` has the same shape, so callers
// should also have a reason to believe it is an audit (a hint, the resource or the label).
export const isAuditedChanges = (value: unknown): value is Record<string, AuditedChange> =>
  isPlainObject(value) && Object.keys(value).length > 0 && Object.values(value).every((v) => Array.isArray(v) && v.length === 2)

const AUDIT_LABEL = /audited[ _]?changes|^changes$/i

// `diff` isn't in the contract yet; a server that sets it opts a node into the diff view outright.
const declaredDiff = (node: object) => (node as { diff?: boolean }).diff === true

// Pairs alone are ambiguous, so detection also needs a declaration, the audits resource or an audit-ish label.
export const auditedChanges = (node: { value?: unknown }, { resource, label = '' }: { resource?: string; label?: string }) =>
  isAuditedChanges(node.value) && (declaredDiff(node) || resource === 'audits' || AUDIT_LABEL.test(label)) ? node.value : undefined
