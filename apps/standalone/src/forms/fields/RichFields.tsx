import { useMemo } from 'react'
import { Input } from '@/components/ui/input'
import { classicUrl } from '@/lib/classic'
import { cn } from '@/lib/utils'
import { NodeContext } from '@/nodes/context'
import { NodeList } from '@/nodes/Node'
import { purify } from '@/sanitize/purify'
import type { FieldProps } from '../context'
import { useRecordFormContext } from '../formContext'
import { FieldShell } from './shell'
import { useField } from './useField'

export function FileField({ field, name }: FieldProps) {
  const state = useField(field, name)
  const { controller, aria } = state
  const current = typeof field.value === 'string' ? field.value : undefined
  return (
    <FieldShell field={field} state={state}>
      <Input {...aria} type="file" name={controller.name} onChange={(e) => controller.onChange(e.target.files?.[0] ?? null)} onBlur={controller.onBlur} />
      {current && !controller.value && (
        <p className="text-xs text-muted-foreground">
          Current file: <span className="font-medium text-foreground">{current.split('/').pop()}</span>. Choose a file to replace it.
        </p>
      )}
    </FieldShell>
  )
}

export function HtmlField({ field }: FieldProps) {
  const { form } = useRecordFormContext()
  const { resource, id } = form.response
  const clean = useMemo(() => purify(String(field.value ?? ''), 'display'), [field.value])
  return (
    <div className={cn('flex w-full max-w-3xl flex-col gap-1.5')}>
      <span className="text-sm font-medium">{field.label}</span>
      <div className="rounded-lg border bg-muted/40 p-3 text-sm">
        <div className="space-y-2 [&_a]:underline [&_ol]:list-decimal [&_ol]:pl-5 [&_ul]:list-disc [&_ul]:pl-5" dangerouslySetInnerHTML={{ __html: clean }} />
        <a href={classicUrl(resource, id, id ? '/edit' : '/new')} className="mt-2 inline-block text-xs text-muted-foreground underline-offset-4 hover:underline">
          Edit this field in classic admin
        </a>
      </div>
    </div>
  )
}

// What the form block printed around its inputs, laid out as a page's content within the form's record.
export function ContentField({ field }: FieldProps) {
  const { form } = useRecordFormContext()
  const { resource, id, display_name: name } = form.response
  return (
    <NodeContext value={{ resource, id, name }}>
      <div className="flex min-w-0 flex-col gap-4">
        <NodeList nodes={field.layout} />
      </div>
    </NodeContext>
  )
}

export const HiddenField = () => null
