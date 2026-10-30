import { useEffect, useEffectEvent, useMemo, useReducer, useRef, useState } from 'react'
import { useForm, type FieldErrors, type Resolver } from 'react-hook-form'
import { toast } from 'sonner'
import { ApiError, isRateLimited, isRetry, isStale } from '@/api/fetcher'
import type { FormResponse, Option } from '@/api/generated/model'
import { classicUrl } from '@/lib/classic'
import { toastError } from '@/lib/apiDenied'
import {
  activeFields,
  collectEntries,
  defaultValues,
  fieldKey,
  initialRows,
  mapErrors,
  mapRowErrors,
  newRow,
  nextRowIndex,
  rowChanges,
  rowsSignature,
  validate,
  type ActiveField,
  type FormValues,
  type Row,
  type RowsBySection,
} from './model'
import type { Entry } from './params'
import { sendWithResend } from './resend'

const RETRY_TOAST = 'save-retry'
export const RETRY_MESSAGE = "Couldn't save right now — trying again…"

type RowAction =
  | { type: 'add'; section: number; row: Row }
  | { type: 'remove' | 'restore'; section: number; rid: string }
  | { type: 'move'; section: number; rid: string; delta: -1 | 1 }

function rowsReducer(rows: RowsBySection, action: RowAction): RowsBySection {
  const list = rows[action.section] ?? []
  const next = (() => {
    switch (action.type) {
      case 'add':
        return [...list, action.row]
      case 'remove':
        // Rows that exist server-side are flagged for `_destroy`; unsaved ones are just dropped.
        return list.flatMap((r) => (r.rid !== action.rid ? [r] : r.isNew ? [] : [{ ...r, removed: true }]))
      case 'restore':
        return list.map((r) => (r.rid === action.rid ? { ...r, removed: false } : r))
      case 'move': {
        const i = list.findIndex((r) => r.rid === action.rid)
        const j = i + action.delta
        if (i < 0 || j < 0 || j >= list.length) return list
        const copy = [...list]
        ;[copy[i], copy[j]] = [copy[j], copy[i]]
        return copy
      }
    }
  })()
  return { ...rows, [action.section]: next }
}

type Options = {
  // Where "Open in classic admin" goes when the form can't be submitted here.
  classicHref?: string
  // Values to re-apply after a stale write was reloaded; they count as unsaved edits.
  carry?: FormValues
}

export function useRecordForm(response: FormResponse, { classicHref, carry }: Options = {}) {
  const { sections } = response.form
  const readOnly = response.submittable === false
  const [stale, setStale] = useState(false)
  const [rows, dispatch] = useReducer(rowsReducer, sections, initialRows)
  const [initialSignature] = useState(() => rowsSignature(rows))
  const [base, setBase] = useState<string[]>([])
  const [rowNotes, setRowNotes] = useState<Record<string, string[]>>({})
  const [pending, setPending] = useState(false)
  const [asking, setAsking] = useState<(ok: boolean) => void>()

  const fields = useMemo(() => activeFields(sections, rows), [sections, rows])
  const fieldsRef = useRef<ActiveField[]>(fields)
  useEffect(() => {
    fieldsRef.current = fields
  }, [fields])

  const resolver: Resolver<FormValues> = async (values) => {
    const messages = validate(fieldsRef.current, values)
    const errors = Object.fromEntries(Object.entries(messages).map(([key, message]) => [key, { type: 'validate', message }]))
    return Object.keys(errors).length ? { values: {}, errors: errors as FieldErrors<FormValues> } : { values, errors: {} }
  }

  const methods = useForm<FormValues>({
    defaultValues: defaultValues(fields),
    resolver,
    mode: 'onTouched',
    shouldUnregister: false,
  })

  const applyCarry = useEffectEvent(() => Object.entries(carry ?? {}).forEach(([key, value]) => methods.setValue(key, value, { shouldDirty: true })))
  useEffect(() => applyCarry(), [])

  const dirty = methods.formState.isDirty || rowsSignature(rows) !== initialSignature

  const addRow = (section: number, initial?: Option) => {
    const index = nextRowIndex(rows[section] ?? [])
    dispatch({ type: 'add', section, row: newRow(sections[section], index, initial) })
  }

  const removeRow = (section: number, rid: string) => {
    const row = rows[section]?.find((r) => r.rid === rid)
    if (row?.isNew) methods.unregister(row.fields.map(fieldKey))
    dispatch({ type: 'remove', section, rid })
  }

  const applyErrors = (error: unknown) => {
    if (!(error instanceof ApiError) || error.status !== 422 || error.code !== 'invalid') return false
    const { row_errors: rowErrors, base: baseErrors } = error.body ?? {}
    const named = mapRowErrors(rowErrors, sections, rows)
    const fieldErrors = Object.entries(error.body?.errors ?? {}).filter(([key]) => !named.handled.has(key.split('.')[0]))
    const mapped = mapErrors(Object.fromEntries(fieldErrors), baseErrors, fieldsRef.current)
    const byKey = { ...mapped.byKey, ...named.byKey }
    setBase(mapped.unmatched.length || Object.keys(byKey).length || Object.keys(named.notes).length ? mapped.unmatched : [error.message])
    setRowNotes(named.notes)
    Object.entries(byKey).forEach(([key, message], i) => methods.setError(key, { type: 'server', message }, { shouldFocus: i === 0 }))
    return true
  }

  // Server `invalid_csrf` is retried in the fetcher and a 429 already toasted there; a stale write opens its
  // dialog; a `retry` (the host's concurrency guard) resends an update once, then offers "Try again"; anything
  // else unexpected becomes a toast.
  const submit = <T>(send: (entries: Entry[]) => Promise<T>, onDone: (result: T) => void) =>
    methods.handleSubmit(async (values) => {
      if (readOnly) return
      if (response.submit_confirm && !(await new Promise<boolean>((resolve) => setAsking(() => resolve)))) return
      const entries = collectEntries(sections, rows, values)
      // Only an update carries the lock that makes an unprompted resend safe.
      const autoResend = !['post', 'get'].includes(response.action.method.toLowerCase())

      const attempt = async (resend: boolean): Promise<void> => {
        setBase([])
        setRowNotes({})
        setPending(true)
        try {
          onDone(await sendWithResend(() => send(entries), resend, () => toast.info(RETRY_MESSAGE, { id: RETRY_TOAST })))
          toast.dismiss(RETRY_TOAST)
        } catch (error) {
          if (isRetry(error)) {
            toast.error("Couldn't save right now", { id: RETRY_TOAST, action: { label: 'Try again', onClick: () => void attempt(false) } })
          } else if (isStale(error)) setStale(true)
          else if (!applyErrors(error) && !isRateLimited(error)) toastError(error)
        } finally {
          setPending(false)
        }
      }
      await attempt(autoResend)
    })

  return {
    response,
    sections,
    rows,
    fields,
    methods,
    base,
    rowNotes,
    changes: rowChanges(rows),
    pending,
    asking,
    answer: (ok: boolean) => {
      asking?.(ok)
      setAsking(undefined)
    },
    dirty,
    readOnly,
    classicHref: classicHref ?? classicUrl(response.resource, response.id, response.id ? '/edit' : '/new'),
    stale,
    setStale,
    submit,
    addRow,
    removeRow,
    restoreRow: (section: number, rid: string) => dispatch({ type: 'restore', section, rid }),
    moveRow: (section: number, rid: string, delta: -1 | 1) => dispatch({ type: 'move', section, rid, delta }),
  }
}

export type RecordFormApi = ReturnType<typeof useRecordForm>
