import { useEffect, useRef, useState, type FocusEvent, type KeyboardEvent, type Ref } from 'react'
import { useWatch } from 'react-hook-form'
import { Pencil, Plus, Trash2, Undo2 } from 'lucide-react'
import type { FormField, FormSection, Option } from '@/api/generated/model'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { cn } from '@/lib/utils'
import { DenseContext } from './fields/dense'
import { OptionList } from './fields/OptionList'
import { useOptionSource } from './fields/useOptionSource'
import { useRecordFormContext } from './formContext'
import { rowLabel } from './rowLabel'
import { FormFieldView, RowNotes } from './rowParts'
import { fieldKey, initialValue, soleControl, type Row } from './model'

const sameValue = (value: unknown) => String(value ?? '').trim().toLowerCase()

// A has_many whose rows are one control each: a list with a line per row and one place to add more.
export function CompactRows({ index, section, title }: { index: number; section: FormSection; title: string }) {
  const { form } = useRecordFormContext()
  const rows = form.rows[index] ?? []
  const active = rows.filter((r) => !r.removed)
  const template = soleControl(section.template_fields ?? [])
  const control = (row: Row) => soleControl(row.fields) as FormField
  const watched = useWatch({ name: active.map((r) => fieldKey(control(r))) })
  const values = new Map(active.map((r, i) => [r.rid, watched[i] ?? initialValue(control(r))]))
  const listed = new Set<string>()
  const repeats = new Set(
    active.filter((r) => {
      const value = sameValue(values.get(r.rid))
      return value && (listed.has(value) || !listed.add(value))
    }).map((r) => r.rid),
  )
  const addRef = useRef<HTMLElement>(null)
  const full = section.max_rows != null && active.length >= section.max_rows
  const add = (initial: Option) => form.addRow(index, initial)

  return (
    <div className="flex flex-col gap-2">
      <ul aria-label={title} className="divide-y overflow-hidden rounded-md border bg-background">
        {rows.length === 0 && <li className="px-3 py-2 text-sm text-muted-foreground">Nothing added yet.</li>}
        {rows.map((row, position) => (
          <CompactRow
            key={row.rid}
            index={index}
            row={row}
            position={position}
            duplicate={repeats.has(row.rid)}
            onEmptied={() => requestAnimationFrame(() => addRef.current?.focus())}
          />
        ))}
        {template && section.new_record_label && (
          <li className="bg-muted/30 p-1">
            {full ? (
              <p className="px-2 py-1.5 text-sm text-muted-foreground">Up to {section.max_rows} rows.</p>
            ) : template.control === 'typeahead' || template.control === 'select' ? (
              <AddPicker
                field={template}
                label={section.new_record_label}
                taken={new Set([...values.values()].map(String))}
                onAdd={add}
                triggerRef={addRef as Ref<HTMLButtonElement>}
              />
            ) : (
              <AddText
                field={template}
                label={section.new_record_label}
                exists={(text) => listed.has(sameValue(text))}
                onAdd={add}
                inputRef={addRef as Ref<HTMLInputElement>}
              />
            )}
          </li>
        )}
      </ul>
      {template?.hint && <p className="text-xs text-muted-foreground">{template.hint}</p>}
    </div>
  )
}

type RowProps = { index: number; row: Row; position: number; duplicate: boolean; onEmptied: () => void }

const CONTROL = 'input, textarea, button[role="combobox"]'

function CompactRow({ index, row, position, duplicate, onEmptied }: RowProps) {
  const { form } = useRecordFormContext()
  const field = soleControl(row.fields) as FormField
  const key = fieldKey(field)
  const label = `${field.label}, row ${position + 1}`
  const { errors } = form.methods.formState
  const failed = !!errors[key] || !!form.rowNotes[row.rid]
  const value = String(useWatch({ name: key }) ?? '')
  const unchanged = value === String(initialValue(field))
  const [editing, setEditing] = useState(false)
  const rowRef = useRef<HTMLLIElement>(null)
  const focus = (selector: string, open = false) =>
    requestAnimationFrame(() => {
      const target = rowRef.current?.querySelector<HTMLElement>(selector)
      target?.focus()
      if (open) target?.click()
    })

  // A saved row's control mounts only after the server rejects it, too late for the form's own focus.
  const firstRejected = errors[key]?.type === 'server' && Object.keys(errors)[0] === key
  useEffect(() => {
    if (firstRejected) focus(CONTROL)
  }, [firstRejected])

  if (row.removed)
    return (
      <li className="flex items-center gap-2 bg-muted/40 py-1.5 pr-2 pl-3">
        <span className="min-w-0 flex-1 truncate text-sm text-muted-foreground line-through decoration-muted-foreground/60">{rowLabel(form, row) ?? `Row ${position + 1}`}</span>
        <span className="text-xs text-muted-foreground">Removing</span>
        <Button type="button" variant="ghost" size="sm" onClick={() => form.restoreRow(index, row.rid)}>
          <Undo2 />
          Undo<span className="sr-only"> removal of row {position + 1}</span>
        </Button>
      </li>
    )

  // Saved rows read as values; a new or changed row, or one the server rejected, shows its control.
  const showControl = row.isNew || editing || failed || !unchanged
  const selected = field.options?.find((o) => o.value === value)
  const text = selected?.label ?? value
  const duplicateBadge = duplicate && <Badge className="bg-warning-soft text-warning">Already listed</Badge>
  const removeButton = row.canRemove && (
    <Button
      type="button"
      variant="ghost"
      size="icon-sm"
      aria-label={`Remove row ${position + 1}`}
      onClick={() => form.removeRow(index, row.rid)}
      className="opacity-0 group-focus-within:opacity-100 group-hover:opacity-100 [@media(hover:none)]:opacity-100"
    >
      <Trash2 />
    </Button>
  )

  if (!showControl)
    return (
      <li ref={rowRef} className="group flex items-center gap-1 border-l-2 border-l-transparent py-1 pr-1.5 pl-2 hover:bg-muted/50">
        <button
          type="button"
          data-edit
          onClick={() => (setEditing(true), focus(CONTROL, true))}
          className="flex min-w-0 flex-1 items-center gap-2 rounded-sm px-1 py-1 text-left outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <span className="sr-only">
            Change {field.label.toLowerCase()}, row {position + 1}:{' '}
          </span>
          <span className="flex min-w-0 flex-1 flex-col">
            <span className="truncate text-sm">{text}</span>
            {selected?.hint && <span className="truncate text-xs text-muted-foreground">{selected.hint}</span>}
          </span>
          <Pencil aria-hidden className="size-3.5 shrink-0 text-muted-foreground opacity-0 group-focus-within:opacity-100 group-hover:opacity-100" />
        </button>
        <span className="flex h-8 shrink-0 items-center gap-1.5">
          {duplicateBadge}
          {removeButton}
        </span>
      </li>
    )

  const keep = () => {
    form.methods.setValue(key, initialValue(field), { shouldDirty: true })
    form.methods.clearErrors(key)
    setEditing(false)
    focus('[data-edit]')
  }

  const onKeyDown = (event: KeyboardEvent<HTMLLIElement>) => {
    // A picker that was open has already taken this Escape.
    if (event.key === 'Escape' && !event.defaultPrevented && !row.isNew) return keep()
    // Backspace in a new row's empty text box takes the row back, as it does in a tag input.
    const target = event.target as HTMLElement
    if (event.key !== 'Backspace' || !row.isNew || !(target instanceof HTMLInputElement) || target.value !== '') return
    event.preventDefault()
    form.removeRow(index, row.rid)
    onEmptied()
  }

  // Leaving an untouched row makes it a plain value again, unless focus went into its open picker.
  const onBlur = (event: FocusEvent<HTMLLIElement>) => {
    const row = event.currentTarget
    if (!unchanged || failed || row.contains(event.relatedTarget) || row.querySelector('[aria-expanded="true"]')) return
    setEditing(false)
  }

  return (
    <li
      ref={rowRef}
      onKeyDown={onKeyDown}
      onBlur={onBlur}
      className={cn('group flex flex-col gap-1 border-l-2 py-1.5 pr-1.5 pl-2', failed ? 'border-l-danger bg-danger-soft/40' : 'border-l-transparent')}
    >
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <DenseContext value={{ label }}>
            <FormFieldView field={{ ...field, hint: undefined }} name={key} />
          </DenseContext>
        </div>
        <span className="flex h-8 shrink-0 items-center gap-1.5">
          {row.isNew && <Badge variant="secondary">New</Badge>}
          {duplicateBadge}
          {removeButton}
        </span>
      </div>
      <RowNotes notes={form.rowNotes[row.rid]} />
    </li>
  )
}

// Enter adds what was typed and keeps the box for the next one; the form never sees that Enter.
function AddText({ field, label, exists, onAdd, inputRef }: { field: FormField; label: string; exists: (text: string) => boolean; onAdd: (option: Option) => void; inputRef: Ref<HTMLInputElement> }) {
  const [text, setText] = useState('')
  const [notice, setNotice] = useState<string>()
  const value = text.trim()

  const commit = () => {
    if (!value) return
    if (exists(value)) return setNotice(`“${value}” is already in the list`)
    onAdd({ label: value, value })
    setText('')
    setNotice(undefined)
  }

  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-2">
        <Input
          ref={inputRef}
          value={text}
          aria-label={label}
          placeholder={`${label}…`}
          maxLength={field.input_html?.maxlength}
          inputMode={field.control === 'number' ? 'decimal' : undefined}
          autoComplete="off"
          aria-invalid={notice ? true : undefined}
          onChange={(e) => (setText(e.target.value), setNotice(undefined))}
          onKeyDown={(e) => {
            if (e.key !== 'Enter') return
            e.preventDefault()
            commit()
          }}
        />
        <Button type="button" variant="outline" size="sm" disabled={!value} onClick={commit}>
          <Plus />
          Add
        </Button>
      </div>
      <p role="status" className="px-1 text-xs text-warning empty:hidden">
        {notice}
      </p>
    </div>
  )
}

// A choice already in the list isn't offered again.
function AddPicker({ field, label, taken, onAdd, triggerRef }: { field: FormField; label: string; taken: Set<string>; onAdd: (option: Option) => void; triggerRef: Ref<HTMLButtonElement> }) {
  const [open, setOpen] = useState(false)
  const remote = !!field.options_path
  const source = useOptionSource({ path: field.options_path, inline: field.options ?? [], selected: [], open })
  const free = (options: Option[]) => options.filter((o) => !taken.has(o.value))

  return (
    <Popover
      open={open}
      onOpenChange={(next) => {
        setOpen(next)
        if (!next) source.setTerm('')
      }}
    >
      <PopoverTrigger asChild>
        <Button ref={triggerRef} type="button" variant="ghost" role="combobox" aria-label={label} aria-expanded={open} className="w-full justify-start font-normal text-muted-foreground">
          <Plus />
          {label}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" aria-label={label} className="w-(--radix-popover-trigger-width) min-w-64 p-0">
        <OptionList
          source={{ ...source, found: free(source.found), recent: free(source.recent) }}
          inline={free(field.options ?? [])}
          remote={remote}
          selected={[]}
          placeholder={`Search ${field.label.toLowerCase()}…`}
          onPick={(option) => {
            source.remember(option)
            onAdd(option)
            setOpen(false)
          }}
          freeText={!!field.free_text}
        />
      </PopoverContent>
    </Popover>
  )
}
