import { Checkbox } from '@/components/ui/checkbox'
import { Label } from '@/components/ui/label'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import type { FieldProps } from '../context'
import { Combobox } from './Combobox'
import { FieldError, FieldShell, Hint, RequiredMark } from './shell'
import { useField } from './useField'

const NONE = '__none__'
const INLINE_SELECT_MAX = 15

export function SelectField({ field, name }: FieldProps) {
  const options = field.options ?? []
  if (field.multiple || field.options_path || options.length > INLINE_SELECT_MAX) return <Combobox field={field} name={name} />

  return <NativeSelect field={field} name={name} />
}

function NativeSelect({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller, aria } = state
  const { id, ref, ...trigger } = aria
  return (
    <FieldShell field={field} state={state}>
      <Select
        // oxlint-disable-next-line react/refs -- false positive: `value` is plain state; only controller.ref is a (callback) ref
        value={String(controller.value ?? '')}
        onValueChange={(v) => controller.onChange(v === NONE ? '' : v)}
        disabled={field.disabled}
        name={controller.name}
      >
        <SelectTrigger id={id} ref={ref} onBlur={controller.onBlur} className="w-full" {...trigger}>
          <SelectValue placeholder={field.placeholder ?? 'Select…'} />
        </SelectTrigger>
        <SelectContent position="popper">
          {!field.required && <SelectItem value={NONE}>None</SelectItem>}
          {field.options?.map((o) => (
            <SelectItem key={o.value} value={o.value}>
              {o.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </FieldShell>
  )
}

export function RadioField({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller, id } = state
  return (
    <FieldShell field={field} state={state} group>
      <RadioGroup
        ref={controller.ref}
        // oxlint-disable-next-line react/refs -- false positive: `value` is plain state; only controller.ref is a (callback) ref
        value={String(controller.value ?? '')}
        onValueChange={controller.onChange}
        onBlur={controller.onBlur}
        disabled={field.disabled}
        aria-invalid={state.error ? true : undefined}
        aria-required={field.required || undefined}
      >
        {field.options?.map((o, i) => (
          <div key={o.value} className="flex items-center gap-2">
            <RadioGroupItem id={`${id}-${i}`} value={o.value} />
            <Label htmlFor={`${id}-${i}`} className="font-normal">
              {o.label}
            </Label>
          </div>
        ))}
      </RadioGroup>
    </FieldShell>
  )
}

export function CheckboxesField({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller, id } = state
  const selected: string[] = controller.value ?? []
  const toggle = (value: string, on: boolean) => controller.onChange(on ? [...selected, value] : selected.filter((v) => v !== value))
  return (
    <FieldShell field={field} state={state} group>
      {field.options?.map((o, i) => (
        <div key={o.value} className="flex items-center gap-2">
          <Checkbox
            id={`${id}-${i}`}
            ref={i === 0 ? controller.ref : undefined}
            checked={selected.includes(o.value)}
            onCheckedChange={(on) => toggle(o.value, on === true)}
            onBlur={controller.onBlur}
            disabled={field.disabled}
          />
          <Label htmlFor={`${id}-${i}`} className="font-normal">
            {o.label}
          </Label>
        </div>
      ))}
    </FieldShell>
  )
}

export function BooleanField({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller, id, error, aria } = state
  return (
    <div className="flex w-full max-w-xl flex-col gap-1.5">
      <div className="flex items-center gap-3">
        <Switch
          id={id}
            ref={controller.ref}
          // oxlint-disable-next-line react/refs -- false positive: `value` is plain state; only controller.ref is a (callback) ref
          checked={!!controller.value}
          onCheckedChange={controller.onChange}
          onBlur={controller.onBlur}
          disabled={field.disabled}
          aria-describedby={aria['aria-describedby']}
          aria-invalid={aria['aria-invalid']}
        />
        <Label htmlFor={id} className="gap-1">
          {field.label}
          {field.required && <RequiredMark />}
        </Label>
      </div>
      {field.hint && <Hint id={id}>{field.hint}</Hint>}
      {error && <FieldError id={id}>{error}</FieldError>}
    </div>
  )
}
