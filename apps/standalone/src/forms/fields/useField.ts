import { useId } from 'react'
import { useController } from 'react-hook-form'
import type { FormField } from '@/api/generated/model'
import { initialValue } from '../model'

export function useField(field: FormField, name: string, live?: (value: unknown) => string | undefined) {
  const { field: controller, fieldState } = useController({ name, defaultValue: initialValue(field) })
  const id = useId()
  const error = live?.(controller.value) ?? fieldState.error?.message ?? field.errors?.[0]
  const describedBy = [field.hint && `${id}-hint`, error && `${id}-error`].filter(Boolean).join(' ') || undefined
  return {
    controller,
    id,
    error,
    // Spread onto the focusable element.
    aria: {
      id,
      ref: controller.ref,
      disabled: field.disabled,
      'aria-invalid': error ? true : undefined,
      'aria-describedby': describedBy,
      'aria-required': field.required || undefined,
    },
  }
}

export type FieldState = ReturnType<typeof useField>
