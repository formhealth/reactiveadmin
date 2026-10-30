import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { cn } from '@/lib/utils'
import type { FieldProps } from '../context'
import { FieldShell } from './shell'
import { useField } from './useField'

const inputType = { email: 'email', url: 'url', phone: 'tel', password: 'password', number: 'number' } as Record<string, string>

export function TextField({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller, aria } = state
  const { rows, min, max, step, maxlength } = field.input_html ?? {}
  const common = { ...aria, name: controller.name, value: String(controller.value ?? ''), onChange: controller.onChange, onBlur: controller.onBlur, placeholder: field.masked ? '••••••' : field.placeholder }

  return (
    <FieldShell field={field} state={state} className={cn(field.control === 'textarea' && 'max-w-3xl')}>
      {field.control === 'textarea' ? (
        <Textarea {...common} rows={rows ?? 4} maxLength={maxlength} className="field-sizing-fixed min-h-0 resize-y" />
      ) : (
        <Input
          {...common}
          type={field.masked ? 'password' : (inputType[field.control] ?? 'text')}
          inputMode={field.control === 'number' ? 'decimal' : undefined}
          autoComplete={field.control === 'password' || field.masked ? 'new-password' : 'off'}
          min={min as number | undefined}
          max={max as number | undefined}
          step={step as number | undefined}
          maxLength={maxlength}
          className={cn(field.control === 'number' && 'max-w-40')}
        />
      )}
    </FieldShell>
  )
}
