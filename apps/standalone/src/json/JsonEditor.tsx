import { useMemo, useRef, useState, type Ref } from 'react'
import { JsonEditor as TreeEditor, type JsonData } from 'json-edit-react'
import { Braces, Brackets, Check, WandSparkles } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { cn } from '@/lib/utils'
import { blank, formatText, parseText, toText } from './editor'
import { maskedNode, treeButtons, treeProps } from './options'
import { Segmented } from './Segmented'
import { MASKED } from './tree'
import { useTreeKeyboard } from './useTreeKeyboard'
import './json.css'

type Mode = 'tree' | 'text'

type Props = {
  value: string
  onChange: (text: string) => void
  onBlur?: () => void
  label: string
  disabled?: boolean
  placeholder?: string
  rows?: number
  // Spread onto the focusable control (id, aria-invalid, aria-describedby) so the field's label and hints attach to it.
  control?: { id?: string; ref?: Ref<HTMLElement>; 'aria-invalid'?: boolean; 'aria-describedby'?: string }
}

// The form keeps the value as JSON text (what the form already submits, parsed on save); the tree edits the parsed
// value and writes it back as text, so key order survives and the two views never disagree.
export function JsonEditor({ value, onChange, onBlur, label, disabled, placeholder, rows = 8, control }: Props) {
  const parsed = useMemo(() => parseText(value), [value])
  const [mode, setMode] = useState<Mode>(parsed.ok ? 'tree' : 'text')
  const textRef = useRef<HTMLTextAreaElement>(null)
  const tree = useTreeKeyboard<HTMLDivElement>(label)
  const { ref: controlRef, ...controlProps } = control ?? {}

  const showMode = (next: Mode) => {
    setMode(next)
    if (next === 'text') requestAnimationFrame(() => textRef.current?.focus())
  }

  const modes: { value: Mode; label: string }[] = [
    { value: 'tree', label: 'Tree' },
    { value: 'text', label: 'Text' },
  ]

  return (
    <div className="flex w-full min-w-0 flex-col gap-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Segmented label="Editor view" value={mode} options={modes} onChange={showMode} />
        {mode === 'text' && (
          <div className="flex items-center gap-2">
            {parsed.ok && !blank(value) && (
              <span className="flex items-center gap-1 text-xs text-success">
                <Check className="size-3.5" aria-hidden />
                Valid JSON
              </span>
            )}
            <Button type="button" variant="outline" size="xs" onClick={() => onChange(formatText(value))} disabled={disabled || !parsed.ok || blank(value)}>
              <WandSparkles />
              Format
            </Button>
          </div>
        )}
      </div>

      {mode === 'text' ? (
        <Textarea
          {...controlProps}
          ref={mergeRefs(textRef, controlRef)}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onBlur={onBlur}
          disabled={disabled}
          rows={Math.min(rows, 24)}
          spellCheck={false}
          placeholder={placeholder ?? '{ }'}
          className="field-sizing-fixed min-h-0 resize-y font-mono text-xs leading-5"
        />
      ) : !parsed.ok ? (
        <Alert variant="warning">
          <AlertDescription className="flex flex-wrap items-center gap-2 text-warning">
            The text isn't valid JSON, so the tree can't show it.
            <Button type="button" variant="outline" size="xs" onClick={() => showMode('text')}>
              Fix in text view
            </Button>
          </AlertDescription>
        </Alert>
      ) : blank(value) ? (
        <div className="flex flex-wrap items-center gap-2 rounded-md border border-dashed p-3 text-xs text-muted-foreground">
          No value.
          <Button type="button" variant="outline" size="xs" disabled={disabled} onClick={() => onChange('{}')}>
            <Braces />
            Start with an object
          </Button>
          <Button type="button" variant="outline" size="xs" disabled={disabled} onClick={() => onChange('[]')}>
            <Brackets />
            Start with a list
          </Button>
        </div>
      ) : (
        <div {...controlProps} {...tree} ref={mergeRefs(tree.ref, controlRef)} className={cn('ra-json max-h-[32rem] overflow-auto rounded-md border bg-card p-2', disabled && 'bg-muted/40')} onBlur={onBlur} aria-disabled={disabled || undefined}>
          <TreeEditor
            data={parsed.value as JsonData}
            setData={(data) => onChange(toText(data))}
            {...treeProps}
            collapse={2}
            allowEdit={!disabled && (({ value }) => value !== MASKED)}
            allowDelete={!disabled}
            allowAdd={!disabled}
            allowDrag={!disabled}
            customNodeDefinitions={[maskedNode]}
            customButtons={treeButtons}
          />
        </div>
      )}
    </div>
  )
}

function mergeRefs<T>(...refs: (Ref<T> | undefined)[]) {
  return (el: T | null) => refs.forEach((ref) => (typeof ref === 'function' ? ref(el) : ref && (ref.current = el)))
}
