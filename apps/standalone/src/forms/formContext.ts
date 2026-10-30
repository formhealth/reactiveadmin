import { createContext, useContext, type ComponentType } from 'react'
import type { FormField, FormFieldControl } from '@/api/generated/model'
import type { RecordFormApi } from './useRecordForm'

export type FieldProps = { field: FormField; name: string }
export type FieldRegistry = Record<FormFieldControl, ComponentType<FieldProps>>

export type FormContextValue = { form: RecordFormApi; registry: FieldRegistry; plain?: boolean }

export const FormContext = createContext<FormContextValue | undefined>(undefined)

export function useRecordFormContext() {
  const ctx = useContext(FormContext)
  if (!ctx) throw new Error('Form fields must render inside <RecordForm>')
  return ctx
}
