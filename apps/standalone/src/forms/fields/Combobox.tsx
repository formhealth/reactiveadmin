import { useState } from 'react'
import { ChevronsUpDown, X } from 'lucide-react'
import type { FormField } from '@/api/generated/model'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import type { FieldProps } from '../context'
import { OptionList } from './OptionList'
import { FieldShell } from './shell'
import { useField } from './useField'
import { useOptionSource } from './useOptionSource'

// Server-searched when the field has `options_path`, otherwise filters `options` in the browser.
export function Combobox({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller, aria } = state
  const multiple = !!field.multiple || field.control === 'multiselect'
  const remote = field.options_path
  const selected: string[] = multiple ? (controller.value ?? []) : controller.value ? [String(controller.value)] : []

  const [open, setOpen] = useState(false)
  const source = useOptionSource({ path: remote, inline: field.options ?? [], selected, open })
  const { labelOf } = source

  const select = (option: { label: string; value: string }) => {
    source.remember(option)
    if (!multiple) {
      controller.onChange(option.value)
      setOpen(false)
    } else controller.onChange(selected.includes(option.value) ? selected.filter((v) => v !== option.value) : [...selected, option.value])
    controller.onBlur()
  }

  const summary = selected.length === 0 ? undefined : multiple ? `${selected.length} selected` : labelOf(selected[0])
  const { id, ref, ...trigger } = aria

  return (
    <FieldShell field={field} state={state}>
      <Popover
        open={open}
        onOpenChange={(next) => {
          setOpen(next)
          if (!next) source.setTerm('')
        }}
      >
        <PopoverTrigger asChild>
          <Button
            id={id}
            ref={ref}
            type="button"
            variant="outline"
            role="combobox"
            aria-expanded={open}
            {...trigger}
            className="w-full justify-between bg-transparent font-normal aria-invalid:border-destructive"
          >
            <span className={summary ? 'truncate' : 'truncate text-muted-foreground'}>{summary ?? field.placeholder ?? 'Select…'}</span>
            <ChevronsUpDown className="size-4 opacity-50" />
          </Button>
        </PopoverTrigger>
        <PopoverContent align="start" aria-label={field.label} className="w-(--radix-popover-trigger-width) min-w-64 p-0">
          <OptionList
            source={source}
            inline={field.options ?? []}
            remote={!!remote}
            selected={selected}
            placeholder={`Search ${field.label.toLowerCase()}…`}
            onPick={select}
            onClear={!multiple && !field.required ? () => (controller.onChange(''), setOpen(false)) : undefined}
            freeText={!!field.free_text}
          />
        </PopoverContent>
      </Popover>
      {multiple && selected.length > 0 && <Chips values={selected} labelOf={labelOf} onRemove={(v) => controller.onChange(selected.filter((s) => s !== v))} field={field} />}
    </FieldShell>
  )
}

function Chips({ values, labelOf, onRemove, field }: { values: string[]; labelOf: (v: string) => string; onRemove: (v: string) => void; field: FormField }) {
  return (
    <ul className="flex flex-wrap gap-1.5">
      {values.map((v) => (
        <li key={v}>
          <Badge variant="secondary" className="h-6 gap-1 pr-1">
            {labelOf(v)}
            <button
              type="button"
              aria-label={`Remove ${labelOf(v)}`}
              disabled={field.disabled}
              onClick={() => onRemove(v)}
              className="rounded-sm p-0.5 outline-none hover:bg-foreground/10 focus-visible:ring-2 focus-visible:ring-ring"
            >
              <X className="size-3" />
            </button>
          </Badge>
        </li>
      ))}
    </ul>
  )
}
