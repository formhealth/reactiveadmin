import { useEffect, useId } from 'react'
import { useFormContext } from 'react-hook-form'
import { Eye, LoaderCircle } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { loadedKey } from '@/forms/model'
import type { FieldProps } from '@/forms/context'
import { FieldShell } from '@/forms/fields/shell'
import { useField } from '@/forms/fields/useField'
import { LazyJsonEditor as JsonEditor } from './lazy'
import { blank, parseText, toText } from './editor'
import { useFullValue } from './expand'
import { MASKED, sizeLabel } from './tree'

const KEY_PREVIEW = 8

// Validated live, not just on submit, so a typo is caught while the cursor is still there.
const liveError = (value: unknown) => {
  const parsed = parseText(String(value ?? ''))
  return parsed.ok ? undefined : `Invalid JSON: ${parsed.error}`
}

export function JsonField({ field, name }: FieldProps) {
  const state = useField(field, name, liveError)
  const { controller, aria } = state
  const { disabled, ...control } = aria
  const { state: expand, load } = useFullValue(field.expand_path)
  const { setValue, resetField } = useFormContext()
  const noteId = useId()
  const text = String(controller.value ?? '')

  // The loaded text becomes the field's baseline: left untouched, it isn't submitted.
  useEffect(() => {
    if (expand.status !== 'loaded') return
    const loaded = toText(expand.value)
    resetField(name, { defaultValue: loaded })
    setValue(loadedKey(name), loaded)
  }, [expand, name, resetField, setValue])

  if (field.summary && blank(text)) {
    const { kind = 'object', keys = [], size = 0 } = field.summary
    const forbidden = expand.status === 'error' && expand.forbidden
    const busy = expand.status === 'loading' || expand.status === 'loaded'
    return (
      <FieldShell field={field} state={state} className="max-w-3xl">
        <div className="flex min-w-0 flex-col gap-1.5">
          <div className="flex flex-wrap items-center gap-1.5 text-xs">
            <Badge variant="secondary" className="font-mono">
              {kind}
            </Badge>
            <span className="text-muted-foreground">{sizeLabel(kind, size)}</span>
            {keys.slice(0, KEY_PREVIEW).map((key) => (
              <code key={key} className="rounded-sm bg-muted px-1.5 py-0.5 font-mono text-muted-foreground">
                {key}
              </code>
            ))}
            {keys.length > KEY_PREVIEW && <span className="text-muted-foreground">+{keys.length - KEY_PREVIEW} more</span>}
          </div>
          {field.expand_path && !forbidden ? (
            <div className="flex flex-wrap items-center gap-2">
              <Button type="button" variant="outline" size="xs" onClick={load} disabled={disabled || busy} aria-describedby={noteId}>
                {busy ? <LoaderCircle className="animate-spin motion-reduce:animate-none" /> : <Eye />}
                {busy ? 'Loading' : expand.status === 'error' ? 'Try again' : 'Load to edit'}
              </Button>
              <span id={noteId} className="text-xs text-muted-foreground">
                Viewing is recorded in the audit log. Saving without loading keeps the stored value.
              </span>
            </div>
          ) : (
            <p className="text-xs text-muted-foreground">{forbidden ? "You can't view this value." : 'This value is kept as stored.'}</p>
          )}
          {expand.status === 'error' && !forbidden && (
            <p role="alert" className="text-xs text-danger">
              Couldn't load the value.
            </p>
          )}
        </div>
      </FieldShell>
    )
  }

  return (
    <FieldShell field={field} state={state} className="max-w-3xl">
      <JsonEditor
        value={text}
        onChange={controller.onChange}
        onBlur={controller.onBlur}
        label={field.label}
        disabled={disabled}
        placeholder={field.placeholder}
        rows={field.input_html?.rows}
        control={control}
      />
      {field.masked && <p className="text-xs text-muted-foreground">The stored value is hidden. Leave this empty to keep it, or enter JSON to replace it.</p>}
      {field.summary && text.includes(MASKED) && <p className="text-xs text-muted-foreground">Masked values stay as stored unless you replace them.</p>}
    </FieldShell>
  )
}
