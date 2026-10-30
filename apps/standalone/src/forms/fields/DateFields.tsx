import { DatePicker } from '@/components/DatePicker'
import { Input } from '@/components/ui/input'
import type { FieldProps } from '../context'
import { dayBounds } from '../model'
import { FieldShell } from './shell'
import { useField, type FieldState } from './useField'

type DayPickerProps = { state: FieldState; field: FieldProps['field']; day: string; onDay: (day: string) => void }

const DayPicker = ({ state, field, day, onDay }: DayPickerProps) => (
  <DatePicker {...state.aria} value={day} onChange={onDay} onCommit={state.controller.onBlur} clearable={!field.required} placeholder={field.placeholder ?? undefined} {...dayBounds(field)} />
)

export function DateField({ field, name }: FieldProps) {
  const state = useField(field, name)
  return (
    <FieldShell field={field} state={state}>
      <DayPicker state={state} field={field} day={String(state.controller.value ?? '')} onDay={state.controller.onChange} />
    </FieldShell>
  )
}

export function DateTimeField({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller } = state
  const [day = '', time = ''] = String(controller.value ?? '').split('T')
  const compose = (nextDay: string, nextTime: string) => controller.onChange(nextDay ? `${nextDay}T${nextTime || '00:00'}` : '')

  return (
    <FieldShell field={field} state={state}>
      <div className="flex flex-wrap gap-2">
        <DayPicker state={state} field={field} day={day} onDay={(d) => compose(d, time)} />
        <Input
          type="time"
          aria-label={`${field.label} time`}
          value={time}
          disabled={field.disabled || !day}
          onChange={(e) => compose(day, e.target.value)}
          onBlur={controller.onBlur}
          className="w-32"
        />
      </div>
    </FieldShell>
  )
}

export function TimeField({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller, aria } = state
  return (
    <FieldShell field={field} state={state}>
      <Input {...aria} type="time" name={controller.name} value={String(controller.value ?? '')} onChange={controller.onChange} onBlur={controller.onBlur} className="w-32" />
    </FieldShell>
  )
}
