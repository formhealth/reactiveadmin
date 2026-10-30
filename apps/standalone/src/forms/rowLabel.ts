import { fieldKey, type Row } from './model'
import type { RecordFormApi } from './useRecordForm'

// What a row shows when it's collapsed to a line: its first control's current value, as its option label if it has one.
export const rowLabel = (form: RecordFormApi, row: Row) => {
  const field = row.fields.find((f) => !['hidden', 'html', 'content'].includes(f.control))
  const value = field && String(form.methods.getValues(fieldKey(field)) ?? '')
  return field?.options?.find((o) => o.value === value)?.label ?? (value || undefined)
}
