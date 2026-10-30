import { useMemo, useState } from 'react'
import { Masked } from '@/components/Masked'
import { cn } from '@/lib/utils'
import type { AuditedChange } from './audit'
import { auditRows, changesBetween, type Change } from './diff'
import { JsonView } from './JsonView'
import { Segmented } from './Segmented'
import { MASKED } from './tree'

export type DiffMode = 'inline' | 'split'
type View = DiffMode | 'raw'

type Props = {
  // Audited changes (`{ field: [old, new] }`) or a plain before/after pair.
  changes?: Record<string, AuditedChange>
  before?: unknown
  after?: unknown
  mode?: DiffMode
  // Offers the raw JSON as a third view; for detected (not declared) audits that may be something else.
  raw?: unknown
  className?: string
}

const tone = {
  removed: 'bg-danger-soft text-danger',
  added: 'bg-success-soft text-success',
}

function Value({ value, absent }: { value: unknown; absent?: boolean }) {
  if (absent) return <span className="text-muted-foreground">—<span className="sr-only">none</span></span>
  if (value === MASKED) return <Masked />
  return <code className="font-mono break-words whitespace-pre-wrap">{typeof value === 'string' ? JSON.stringify(value) : JSON.stringify(value, null, 2)}</code>
}

const Sign = ({ sign, label }: { sign: string; label: string }) => (
  <span aria-hidden className="select-none" title={label}>
    {sign}
  </span>
)

const has = (change: Change, side: 'before' | 'after') => (side === 'before' ? change.op !== 'added' : change.op !== 'removed')

function Inline({ rows }: { rows: Change[] }) {
  return (
    <ul className="flex flex-col divide-y rounded-md border text-xs">
      {rows.map((row) => (
        <li key={row.path} className="flex flex-col gap-1 p-2">
          <code className="font-mono font-semibold">{row.path}</code>
          {has(row, 'before') && (
            <div className={cn('flex gap-2 rounded-sm px-2 py-1', tone.removed)}>
              <Sign sign="−" label="Before" />
              <span className="sr-only">Before:</span>
              <Value value={row.before} />
            </div>
          )}
          {has(row, 'after') && (
            <div className={cn('flex gap-2 rounded-sm px-2 py-1', tone.added)}>
              <Sign sign="+" label="After" />
              <span className="sr-only">After:</span>
              <Value value={row.after} />
            </div>
          )}
        </li>
      ))}
    </ul>
  )
}

function Split({ rows }: { rows: Change[] }) {
  return (
    <div role="table" aria-label="Changes" className="overflow-hidden rounded-md border text-xs">
      <div role="row" className="hidden bg-muted/60 font-semibold text-muted-foreground sm:grid sm:grid-cols-[minmax(7rem,14rem)_1fr_1fr]">
        <div role="columnheader" className="p-2">Field</div>
        <div role="columnheader" className="p-2">Before</div>
        <div role="columnheader" className="p-2">After</div>
      </div>
      {rows.map((row) => (
        <div key={row.path} role="row" className="grid border-t first:border-t-0 sm:grid-cols-[minmax(7rem,14rem)_1fr_1fr]">
          <code role="rowheader" className="p-2 font-mono font-semibold break-words">{row.path}</code>
          <div role="cell" className={cn('min-w-0 p-2', has(row, 'before') && tone.removed)}>
            <span className="mb-0.5 block text-[0.6875rem] uppercase text-muted-foreground sm:hidden">Before</span>
            <Value value={row.before} absent={!has(row, 'before')} />
          </div>
          <div role="cell" className={cn('min-w-0 p-2', has(row, 'after') && tone.added)}>
            <span className="mb-0.5 block text-[0.6875rem] uppercase text-muted-foreground sm:hidden">After</span>
            <Value value={row.after} absent={!has(row, 'after')} />
          </div>
        </div>
      ))}
    </div>
  )
}

export function JsonDiff({ changes, before, after, mode = 'inline', raw, className }: Props) {
  const [view, setView] = useState<View>(mode)
  const rows = useMemo(() => (changes ? auditRows(changes) : changesBetween(before, after)), [changes, before, after])
  const options = [
    { value: 'inline' as const, label: 'Inline' },
    { value: 'split' as const, label: 'Side by side' },
    ...(raw !== undefined ? [{ value: 'raw' as const, label: 'JSON' }] : []),
  ]

  return (
    <div className={cn('flex min-w-0 max-w-full flex-col gap-2', className)}>
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs text-muted-foreground">{rows.length === 0 ? 'No changes' : `${rows.length} ${rows.length === 1 ? 'change' : 'changes'}`}</span>
        <Segmented label="Diff view" value={view} options={options} onChange={setView} />
      </div>
      {view === 'raw' ? <JsonView value={raw} label="Changes" /> : rows.length === 0 ? null : view === 'inline' ? <Inline rows={rows} /> : <Split rows={rows} />}
    </div>
  )
}
