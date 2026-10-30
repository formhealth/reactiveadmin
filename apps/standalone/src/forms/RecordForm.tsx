import { useEffect, useRef } from 'react'
import { ArrowDown, ArrowUp, CircleAlert, ExternalLink, Info, Plus, Trash2, Undo2 } from 'lucide-react'
import type { FormSection } from '@/api/generated/model'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { ConfirmDialog } from './ConfirmDialog'
import { CompactRows } from './CompactRows'
import { RecordFormProvider, type FieldRegistry } from './context'
import { useRecordFormContext } from './formContext'
import { humanize } from '@/lib/humanize'
import { changeSummary, fieldKey, isCompact, type Row } from './model'
import { defaultRegistry } from './registry'
import { rowLabel } from './rowLabel'
import { FormFieldView, RowNotes } from './rowParts'
import type { RecordFormApi } from './useRecordForm'

export { FormFieldView }

// Long titles carry instructions after " - ": keep the heading short and the rest as help text.
const splitTitle = (title: string): [string, string?] => {
  const [head, ...rest] = title.split(' - ')
  const help = rest.join(' - ')
  return [head, help && help.charAt(0).toUpperCase() + help.slice(1)]
}

// `bare`: a run of content with no inputs in it needs no card around it.
function SectionFrame({ title, bare, children }: { title?: string | null; bare?: boolean; children: React.ReactNode }) {
  const { plain } = useRecordFormContext()
  const [head, help] = title ? splitTitle(title) : []
  if (bare) return <div className="flex min-w-0 flex-col gap-5">{children}</div>
  return (
    <fieldset className={cn('min-w-0', !plain && 'rounded-lg border bg-card p-4 sm:p-5')}>
      {head && (
        <legend className="float-left mb-4 w-full text-base font-semibold">
          {head}
          {help && <span className="mt-0.5 block text-sm font-normal text-muted-foreground">{help}</span>}
        </legend>
      )}
      <div className="clear-both flex flex-col gap-5">{children}</div>
    </fieldset>
  )
}

function RowView({ index, row, position, count, section }: { index: number; row: Row; position: number; count: number; section: FormSection }) {
  const { form } = useRecordFormContext()
  if (row.removed)
    return (
      <li className="flex items-center justify-between gap-3 rounded-md border border-dashed bg-muted/40 px-3 py-2">
        <span className="text-sm text-muted-foreground line-through decoration-muted-foreground/60">
          {rowLabel(form, row) ?? `Row ${position + 1}`}
        </span>
        <span className="flex items-center gap-2">
          <span className="text-xs font-medium text-danger">Will be deleted on save</span>
          <Button type="button" variant="ghost" size="sm" onClick={() => form.restoreRow(index, row.rid)}>
            <Undo2 />
            Undo
          </Button>
        </span>
      </li>
    )

  return (
    <li className="flex items-start gap-2 rounded-md border bg-background p-3">
      <div className="grid min-w-0 flex-1 grid-cols-[repeat(auto-fit,minmax(min(100%,14rem),1fr))] gap-4">
        {row.fields.map((f) => (
          <FormFieldView key={fieldKey(f)} field={f} name={fieldKey(f)} />
        ))}
        <RowNotes notes={form.rowNotes[row.rid]} />
      </div>
      <div className="flex shrink-0 items-center gap-0.5 pt-5">
        {section.sortable && (
          <>
            <Button type="button" variant="ghost" size="icon-sm" aria-label={`Move row ${position + 1} up`} disabled={position === 0} onClick={() => form.moveRow(index, row.rid, -1)}>
              <ArrowUp />
            </Button>
            <Button type="button" variant="ghost" size="icon-sm" aria-label={`Move row ${position + 1} down`} disabled={position === count - 1} onClick={() => form.moveRow(index, row.rid, 1)}>
              <ArrowDown />
            </Button>
          </>
        )}
        {row.canRemove && (
          <Button type="button" variant="ghost" size="icon-sm" aria-label={`Remove row ${position + 1}`} onClick={() => form.removeRow(index, row.rid)}>
            <Trash2 />
          </Button>
        )}
      </div>
    </li>
  )
}

function HasManySection({ index, section }: { index: number; section: FormSection }) {
  const { form } = useRecordFormContext()
  const rows = form.rows[index] ?? []
  const title = section.title ?? humanize(section.name ?? '')
  if (isCompact(section))
    return (
      <SectionFrame title={title}>
        <CompactRows index={index} section={section} title={title} />
      </SectionFrame>
    )
  return (
    <SectionFrame title={title}>
      {rows.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nothing added yet.</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {rows.map((row, position) => (
            <RowView key={row.rid} index={index} row={row} position={position} count={rows.length} section={section} />
          ))}
        </ul>
      )}
      {section.new_record_label && (
        <Button type="button" variant="outline" className="self-start" onClick={() => form.addRow(index)}>
          <Plus />
          {section.new_record_label}
        </Button>
      )}
    </SectionFrame>
  )
}

function Sections() {
  const { form } = useRecordFormContext()
  return form.sections.map((section, index) =>
    section.kind === 'has_many' ? (
      <HasManySection key={index} index={index} section={section} />
    ) : (
      <SectionFrame key={index} title={section.title} bare={!section.title && section.fields.every((f) => f.control === 'content')}>
        {section.fields.map((field) => (
          <FormFieldView key={fieldKey(field)} field={field} name={fieldKey(field)} />
        ))}
      </SectionFrame>
    ),
  )
}

// The save bar's status: that something is unsaved, and how many rows it adds and removes.
export function FormStatus({ form }: { form: RecordFormApi }) {
  const summary = changeSummary(form.changes)
  return (
    <p className="text-sm text-muted-foreground" aria-live="polite">
      {form.dirty ? (summary ? `Unsaved: ${summary}` : 'Unsaved changes') : ''}
    </p>
  )
}

export function BaseErrors({ form }: { form: RecordFormApi }) {
  const ref = useRef<HTMLDivElement>(null)
  const hasFieldErrors = Object.keys(form.methods.formState.errors).length > 0
  useEffect(() => {
    if (form.base.length && !hasFieldErrors) ref.current?.focus()
  }, [form.base, hasFieldErrors])

  if (!form.base.length) return null
  return (
    <Alert ref={ref} variant="destructive" tabIndex={-1} className="outline-none">
      <CircleAlert />
      <AlertTitle>{form.base.length > 1 ? "This couldn't be saved" : form.base[0]}</AlertTitle>
      {form.base.length > 1 && (
        <AlertDescription>
          <ul className="list-disc pl-4">
            {form.base.map((message) => (
              <li key={message}>{message}</li>
            ))}
          </ul>
        </AlertDescription>
      )}
    </Alert>
  )
}

function ReadOnlyNotice({ form }: { form: RecordFormApi }) {
  if (!form.readOnly) return null
  return (
    <Alert>
      <Info />
      <AlertTitle>This form can't be saved here</AlertTitle>
      <AlertDescription>
        <p>{form.response.unsupported_reason || "It uses inputs this editor can't reproduce faithfully."}</p>
        <p className="text-muted-foreground">You can look it over here and make changes in classic admin.</p>
      </AlertDescription>
    </Alert>
  )
}

// Replaces Save when the server says the form can't be submitted faithfully from here.
export function SubmitButton({ form, label, pendingLabel = 'Saving…' }: { form: RecordFormApi; label: string; pendingLabel?: string }) {
  if (form.readOnly)
    return (
      <Button asChild>
        <a href={form.classicHref}>
          Open in classic admin
          <ExternalLink />
        </a>
      </Button>
    )
  return (
    <Button type="submit" disabled={form.pending}>
      {form.pending ? pendingLabel : label}
    </Button>
  )
}

type RecordFormProps = {
  form: RecordFormApi
  onSubmit: React.FormEventHandler<HTMLFormElement>
  fields?: Partial<FieldRegistry>
  // Drops the card chrome around sections, for forms that already sit inside a dialog.
  plain?: boolean
  className?: string
  children?: React.ReactNode
}

// Hosts replace a control by passing `fields={{ date: MyDatePicker }}`.
export function RecordForm({ form, onSubmit, fields, plain, className, children }: RecordFormProps) {
  return (
    <RecordFormProvider form={form} registry={{ ...defaultRegistry, ...fields }} plain={plain}>
      <form noValidate onSubmit={onSubmit} className={cn('flex flex-col gap-4', className)}>
        <ReadOnlyNotice form={form} />
        <BaseErrors form={form} />
        <fieldset disabled={form.readOnly} className="contents">
          <Sections />
        </fieldset>
        {children}
      </form>
      <ConfirmDialog title={form.response.submit_label || 'Submit'} question={form.asking && form.response.submit_confirm} answer={form.answer} />
    </RecordFormProvider>
  )
}
