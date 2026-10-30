import { format, isValid, parseISO } from 'date-fns'
import { z } from 'zod'
import type { FormField, FormRecord, FormSection, Option, ValidationErrorRowErrors } from '@/api/generated/model'
import { capitalize, humanize } from '@/lib/humanize'
import type { Entry } from './params'

export type FormValues = Record<string, unknown>

export type Row = {
  rid: string
  id?: string
  base: string
  fields: FormField[]
  isNew: boolean
  removed: boolean
  canRemove: boolean
}

export type RowsBySection = Record<number, Row[]>

export type ActiveField = { key: string; field: FormField; assoc?: string }

const NO_INPUT = new Set(['html', 'content', 'hidden'])

// RHF treats `.` and `[]` in names as paths, so params are flattened into plain keys.
export const fieldKey = (field: Pick<FormField, 'name' | 'param'>) =>
  (field.param ?? field.name)
    .replace(/\[\]$/, '')
    .replace(/\[/g, '__')
    .replace(/\]/g, '')
    .replace(/\W/g, '_')

// Where a summarized json field keeps the text it was loaded as, so an untouched load is not written back.
export const loadedKey = (key: string) => `${key}__loaded`

const attrOf = (param?: string | null) => /([^[\]]+)(\[\])?$/.exec(param ?? '')?.[1]

const text = (value: unknown) => (value == null ? '' : String(value))

const asArray = (value: unknown) => (Array.isArray(value) ? value.map(String) : value == null || value === '' ? [] : [String(value)])

const timeOf = (value: unknown) => /(\d{2}:\d{2})/.exec(text(value))?.[1] ?? ''

const localDateTime = (value: unknown) => {
  const date = parseISO(text(value))
  return isValid(date) ? format(date, "yyyy-MM-dd'T'HH:mm") : ''
}

// The days a date or datetime control allows, as local `yyyy-MM-dd` (a datetime bound is an instant).
export function dayBounds({ control, input_html }: Pick<FormField, 'control' | 'input_html'>) {
  const dayOf = (bound: unknown) => (control === 'datetime' ? localDateTime(bound).slice(0, 10) : text(bound).slice(0, 10)) || undefined
  return { min: dayOf(input_html?.min), max: dayOf(input_html?.max) }
}

export function initialValue(field: FormField): unknown {
  const { value } = field
  switch (field.control) {
    case 'boolean':
      return value === true || value === 'true' || value === '1' || value === 1
    case 'multiselect':
    case 'checkboxes':
      return asArray(value)
    case 'select':
    case 'typeahead':
      return field.multiple ? asArray(value) : text(value)
    case 'json':
      return value == null ? '' : JSON.stringify(value, null, 2)
    case 'file':
      return null
    case 'date':
      return text(value).slice(0, 10)
    case 'datetime':
      return value ? localDateTime(value) : ''
    case 'time':
      return timeOf(value)
    default:
      return text(value)
  }
}

export const jsonError = (source: string) => {
  if (!source.trim()) return undefined
  try {
    JSON.parse(source)
  } catch (e) {
    return `Invalid JSON: ${(e as Error).message}`
  }
}

export function submitValue(field: FormField, value: unknown): unknown {
  switch (field.control) {
    case 'json':
      return text(value).trim() ? JSON.parse(text(value)) : null
    case 'number':
      return text(value) === '' ? '' : Number(value)
    case 'file':
      return value ?? undefined
    default:
      return value
  }
}

const limit = (bound: unknown) => (bound == null || bound === '' || Number.isNaN(Number(bound)) ? undefined : Number(bound))

function dayRange(field: FormField): [(v: string) => boolean, string] | undefined {
  const { min, max } = dayBounds(field)
  if (!min && !max) return undefined
  const message = min && max ? `Choose a date from ${min} to ${max}` : min ? `Choose a date on or after ${min}` : `Choose a date on or before ${max}`
  return [(v) => (!min || v.slice(0, 10) >= min) && (!max || v.slice(0, 10) <= max), message]
}

function schemaFor(field: FormField): z.ZodType {
  const { control } = field
  // A masked secret is never sent back; blank keeps the stored value.
  const required = field.required && !field.masked && !field.summary
  const blank = 'Required'
  if (control === 'boolean') return z.boolean()
  if (control === 'file') return required && !field.value ? z.instanceof(File, { error: blank }) : z.any().optional()
  if (control === 'multiselect' || control === 'checkboxes' || field.multiple)
    return required ? z.array(z.string()).min(1, blank) : z.array(z.string())

  let schema = z.string()
  const { min, max, maxlength } = { min: limit(field.input_html?.min), max: limit(field.input_html?.max), maxlength: field.input_html?.maxlength }
  if (maxlength) schema = schema.max(maxlength, `Use ${maxlength} characters or fewer`)

  const checks: Record<string, [(v: string) => boolean, string] | undefined> = {
    email: [(v) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v), 'Enter a valid email address'],
    url: [(v) => URL.canParse(v), 'Enter a valid URL, including https://'],
    date: dayRange(field),
    datetime: dayRange(field),
    number: [
      (v) => Number.isFinite(Number(v)) && (min === undefined || Number(v) >= min) && (max === undefined || Number(v) <= max),
      min !== undefined && max !== undefined ? `Enter a number from ${min} to ${max}` : min !== undefined ? `Enter a number of ${min} or more` : max !== undefined ? `Enter a number of ${max} or less` : 'Enter a number',
    ],
  }
  const check = checks[control]
  const validated = schema.superRefine((v, ctx) => {
    if (v === '') return
    if (check && !check[0](v)) ctx.addIssue({ code: 'custom', message: check[1] })
    if (control === 'json') {
      const error = jsonError(v)
      if (error) ctx.addIssue({ code: 'custom', message: error })
    }
  })
  return required ? validated.refine((v) => v.trim() !== '', blank) : validated
}

export const buildSchema = (fields: ActiveField[]) =>
  z.object(Object.fromEntries(fields.filter(({ field }) => !field.disabled && !NO_INPUT.has(field.control)).map(({ key, field }) => [key, schemaFor(field)])))

// First message per field key, empty when valid.
export function validate(fields: ActiveField[], values: FormValues): Record<string, string> {
  const result = buildSchema(fields).safeParse(values)
  if (result.success) return {}
  const errors: Record<string, string> = {}
  for (const issue of result.error.issues) errors[String(issue.path[0])] ??= issue.message
  return errors
}

const rowIndex = (base: string) => Number(/\[(\d+)\]$/.exec(base)?.[1] ?? -1)

export const nextRowIndex = (rows: Row[]) => Math.max(-1, ...rows.map((r) => rowIndex(r.base))) + 1

export const existingRow = (section: FormSection, record: FormRecord, position: number): Row => ({
  rid: `r${record.id ?? position}`,
  id: record.id,
  base: record.param ?? `${section.param}[${position}]`,
  fields: record.fields,
  isNew: false,
  removed: false,
  canRemove: !!section.allow_destroy && record.destroy !== false,
})

// `initial` is the choice a compact list's add control was used with: it becomes the new row's value.
export const newRow = (section: FormSection, index: number, initial?: Option): Row => ({
  rid: `n${index}`,
  base: `${section.param}[${index}]`,
  fields: (section.template_fields ?? []).map((f) => {
    const field = { ...f, param: f.param?.replace('__INDEX__', String(index)) }
    return initial && !NO_INPUT.has(f.control) ? { ...field, value: initial.value, options: f.control === 'typeahead' ? [initial] : f.options } : field
  }),
  isNew: true,
  removed: false,
  canRemove: true,
})

const COMPACT_CONTROLS = new Set(['text', 'email', 'url', 'phone', 'number', 'select', 'typeahead'])

// The one control a row holds, when it holds exactly one (the hidden id and `_destroy` don't count).
export const soleControl = (fields: FormField[]) => {
  const inputs = fields.filter((f) => !NO_INPUT.has(f.control))
  return inputs.length === 1 ? inputs[0] : undefined
}

// The server's `compact` hint is honored only while every row really is a single simple control.
export const isCompact = (section: FormSection) =>
  section.layout === 'compact' &&
  [section.template_fields, ...(section.records ?? []).map((r) => r.fields)].every((fields) => {
    const control = fields && soleControl(fields)
    return !fields || (!!control && COMPACT_CONTROLS.has(control.control) && !control.multiple)
  })

export function rowChanges(rows: RowsBySection) {
  const all = Object.values(rows).flat()
  return { add: all.filter((r) => r.isNew && !r.removed).length, remove: all.filter((r) => r.removed).length }
}

export const changeSummary = ({ add, remove }: ReturnType<typeof rowChanges>) =>
  [add && `${add} to add`, remove && `${remove} to remove`].filter(Boolean).join(', ')

export const initialRows = (sections: FormSection[]): RowsBySection =>
  Object.fromEntries(
    sections.flatMap((section, i) => (section.kind === 'has_many' ? [[i, (section.records ?? []).map((r, p) => existingRow(section, r, p))]] : [])),
  )

export function activeFields(sections: FormSection[], rows: RowsBySection): ActiveField[] {
  return sections.flatMap((section, i) =>
    section.kind === 'has_many'
      ? (rows[i] ?? []).filter((r) => !r.removed).flatMap((r) => r.fields.map((field) => ({ key: fieldKey(field), field, assoc: section.name })))
      : section.fields.map((field) => ({ key: fieldKey(field), field })),
  )

}

export const defaultValues = (fields: ActiveField[]): FormValues =>
  Object.fromEntries(fields.filter(({ field }) => !NO_INPUT.has(field.control)).map(({ key, field }) => [key, initialValue(field)]))

export const rowsSignature = (rows: RowsBySection) => JSON.stringify(Object.values(rows).map((list) => list.map((r) => [r.rid, r.removed])))

// A summarized json field is sent only once it was loaded and edited; omitted, the server keeps the stored value.
const unchangedJson = (field: FormField, values: FormValues) => {
  const key = fieldKey(field)
  const text = values[key]
  return text == null || text === '' || text === values[loadedKey(key)]
}

const entryFor = (field: FormField, values: FormValues): Entry[] => {
  if (!field.param || field.disabled || field.control === 'html') return []
  const value = field.control === 'hidden' ? field.value : submitValue(field, values[fieldKey(field)])
  if (field.masked && (value === undefined || value === null || value === '')) return []
  if (field.summary && unchangedJson(field, values)) return []
  if (field.control === 'radio' && value === '') return []
  return value === undefined ? [] : [[field.param, value]]
}

export function collectEntries(sections: FormSection[], rows: RowsBySection, values: FormValues): Entry[] {
  return sections.flatMap((section, i) => {
    if (section.kind !== 'has_many') return section.fields.flatMap((f) => entryFor(f, values))
    let position = 0
    return (rows[i] ?? []).flatMap((row): Entry[] => {
      if (row.removed) return [[`${row.base}[id]`, row.id], [`${row.base}[_destroy]`, '1']]
      const id: Entry[] = row.id && !row.fields.some((f) => f.name === 'id') ? [[`${row.base}[id]`, row.id]] : []
      const order: Entry[] = section.sortable ? [[`${row.base}[${section.sortable}]`, position++]] : []
      return [...id, ...order, ...row.fields.flatMap((f) => entryFor(f, values))]
    })
  })
}

const matchesAttr = (field: FormField, attr: string) => !NO_INPUT.has(field.control) && [field.name, attrOf(field.param), `${field.name}_id`].includes(attr)

// A rejected write names the rows that failed: a saved row by id, a new one by its place among the new rows.
// Their field messages land on the row's own fields; `handled` are the associations `mapErrors` should skip.
export function mapRowErrors(rowErrors: ValidationErrorRowErrors = {}, sections: FormSection[], rows: RowsBySection) {
  const byKey: Record<string, string> = {}
  const notes: Record<string, string[]> = {}
  sections.forEach((section, i) => {
    const failed = section.name ? rowErrors[section.name] : undefined
    if (!failed) return
    const fresh = (rows[i] ?? []).filter((r) => r.isNew && !r.removed)
    for (const { id, new: place, errors } of failed) {
      const row = id === undefined ? (place === undefined ? undefined : fresh[place]) : rows[i]?.find((r) => r.id === id)
      if (!row) continue
      for (const [attr, messages] of Object.entries(errors)) {
        const field = attr === 'base' ? undefined : row.fields.find((f) => matchesAttr(f, attr))
        if (field) byKey[fieldKey(field)] ??= capitalize(messages[0])
        else (notes[row.rid] ??= []).push(...messages.map((m) => (attr === 'base' ? capitalize(m) : `${humanize(attr)} ${m}`)))
      }
    }
  })
  return { byKey, notes, handled: new Set(Object.keys(rowErrors)) }
}

// Server keys are attribute names (`editor_id`, `desk_members.user_email`), not params.
export function mapErrors(errors: Record<string, string[]> = {}, base: string[] = [], fields: ActiveField[]) {
  const byKey: Record<string, string> = {}
  const unmatched = [...base]
  for (const [key, messages] of Object.entries(errors)) {
    const [assoc, attr] = key.includes('.') ? key.split('.', 2) : [undefined, key]
    const candidates = fields.filter(
      (f) => f.assoc === assoc && matchesAttr(f.field, attr),
    )
    if (candidates.length === 1) byKey[candidates[0].key] = capitalize(messages[0])
    else unmatched.push(...messages.map((m) => `${humanize(key)} ${m}`))
  }
  return { byKey, unmatched }
}
