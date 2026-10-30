import type { FormField, FormResponse } from '@/api/generated/model'
import { defaultValues, fieldKey, type FormValues } from './model'

export type Change = { key: string; label: string; server: string; yours: string; conflict: boolean }

export type Review = {
  changes: Change[]
  // Values to re-apply on top of the fresh form.
  carry: FormValues
  // Fields someone else changed that you didn't touch; they simply stay as the server has them.
  theirs: string[]
}

// Hidden, html, file and masked inputs have no value worth comparing.
const comparable = (field: FormField) => !['hidden', 'html', 'content', 'file'].includes(field.control) && !field.masked && !field.disabled

const inputsOf = (response: FormResponse) => response.form.sections.filter((s) => s.kind !== 'has_many').flatMap((s) => s.fields.filter(comparable))

const same = (a: unknown, b: unknown) => JSON.stringify(a ?? '') === JSON.stringify(b ?? '')

export const show = (field: FormField, value: unknown) => {
  const list = Array.isArray(value) ? value : [value]
  const label = (v: unknown) => (field.control === 'boolean' ? (v ? 'Yes' : 'No') : (field.options?.find((o) => o.value === String(v))?.label ?? String(v)))
  return list.filter((v) => v !== '' && v != null).map(label).join(', ') || '—'
}

// What `mine` (the form's current values) changed against what you opened, set against the server's latest.
// Only fields you edited are carried over: re-applying the rest would overwrite someone else's work with stale values.
export function reviewStale(opened: FormResponse, fresh: FormResponse, mine: FormValues): Review {
  const base = defaultValues(inputsOf(opened).map((field) => ({ key: fieldKey(field), field })))
  const latestFields = new Map(inputsOf(fresh).map((field) => [fieldKey(field), field]))
  const latest = defaultValues([...latestFields].map(([key, field]) => ({ key, field })))
  const review: Review = { changes: [], carry: {}, theirs: [] }

  for (const field of inputsOf(opened)) {
    const key = fieldKey(field)
    const server = latestFields.get(key)
    if (!server) continue
    const edited = !same(mine[key], base[key])
    const moved = !same(latest[key], base[key])
    if (!edited) {
      if (moved) review.theirs.push(field.label)
    } else if (!same(mine[key], latest[key])) {
      review.carry[key] = mine[key]
      review.changes.push({ key, label: field.label, server: show(server, latest[key]), yours: show(field, mine[key]), conflict: moved })
    }
  }
  return review
}
