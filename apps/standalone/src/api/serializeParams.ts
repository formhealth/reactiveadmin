import { flag } from '@/forms/query'

const pairs = (key: string, value: unknown): [string, string][] =>
  value === undefined
    ? []
    : Array.isArray(value)
      ? value.flatMap((v) => pairs(`${key}[]`, v))
      : value !== null && typeof value === 'object'
        ? Object.entries(value).flatMap(([k, v]) => pairs(`${key}[${k}]`, v))
        : [[key, flag(value)]]

// The document declares `form_fields` as an exploded form object: its keys are already the full param names (`report[term]`, `tags[]`).
const formFields = (fields: Record<string, unknown>) =>
  Object.entries(fields).flatMap(([k, v]) => (Array.isArray(v) ? v.flatMap((item) => pairs(k.endsWith('[]') ? k : `${k}[]`, item)) : pairs(k, v)))

// Rails' query format: `q[weight_in][]=1&q[weight_in][]=2`. Orval's default would send `q[weight_in]=1,2`.
export const serializeParams = (params: Record<string, unknown> = {}) =>
  new URLSearchParams(Object.entries(params).flatMap(([k, v]) => (k === 'form_fields' && v && typeof v === 'object' ? formFields(v as Record<string, unknown>) : pairs(k, v)))).toString()
