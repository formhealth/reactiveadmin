import { prettifyError, type ZodType } from 'zod'
import * as schemas from './generated/zod/core'

export type ContractKey = Extract<keyof typeof schemas, `${string}Response`>

// Responses checked by path. Custom actions and pages are served at paths that look like a record's or an index's,
// so their callers name the schema instead (`contract`). Nested resources' paths match nothing and go unchecked.
export const ROUTES: [method: string, template: string, schema: ContractKey][] = [
  ['GET', '/admin/_manifest', 'GetManifestResponse'],
  ['GET', '/admin/_session', 'GetSessionResponse'],
  ['GET', '/admin/_pages/{page}', 'GetPageResponse'],
  ['GET', '/admin/{resource}/_meta', 'GetResourceMetaResponse'],
  ['GET', '/admin/{resource}/_options', 'GetOptionsResponse'],
  ['GET', '/admin/{resource}/_options/lookup', 'LookupOptionsResponse'],
  ['GET', '/admin/{resource}/_labels', 'GetLabelsResponse'],
  ['GET', '/admin/{resource}/new', 'GetNewFormResponse'],
  ['GET', '/admin/{resource}/{id}/edit', 'GetEditFormResponse'],
  ['GET', '/admin/{resource}/{id}/_value', 'GetRecordValueResponse'],
  ['GET', '/admin/{resource}', 'ListRecordsResponse'],
  ['GET', '/admin/{resource}/{id}', 'GetRecordResponse'],
  ['POST', '/admin/{resource}', 'CreateRecordResponse'],
  ['POST', '/admin/{resource}/batch_action', 'RunBatchActionResponse'],
  ['PATCH', '/admin/{resource}/{id}', 'UpdateRecordResponse'],
  ['DELETE', '/admin/{resource}/{id}', 'DestroyRecordResponse'],
]

const literals = (template: string) => template.split('/').filter((part) => part && !part.startsWith('{')).length

// Most literal first, so `/admin/{resource}/new` wins over `/admin/{resource}/{id}`.
const patterns = ROUTES.map(([method, template, schema]) => ({
  method,
  pattern: new RegExp(`^${template.replace(/\{\w+\}/g, '[^/]+')}$`),
  schema,
  rank: literals(template),
})).sort((a, b) => b.rank - a.rank)

export const schemaFor = (method: string, path: string): ContractKey | undefined =>
  patterns.find((route) => route.method === method && route.pattern.test(path))?.schema

export const violations: string[] = []

// Loud on purpose: the crawl fails on console errors and the story runner on `violations`. The message names the
// request and the failing keys, never values.
export function checkResponse(method: string, path: string, body: unknown, contract?: ContractKey) {
  const key = contract ?? schemaFor(method, path)
  if (!key) return
  const result = (schemas[key] as ZodType).safeParse(body)
  if (result.success) return
  const message = `${method} ${path} doesn't match ${key} in core.yaml:\n${prettifyError(result.error)}`
  violations.push(message)
  console.error(message)
}
