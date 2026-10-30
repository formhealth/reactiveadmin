import { useId } from 'react'
import { useLocation } from 'react-router'
import { Eye, EyeOff, ExternalLink, LoaderCircle, TriangleAlert } from 'lucide-react'
import type { NodeSummary } from '@/api/generated/model'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { classicHere } from '@/boundaries/urls'
import { classicUrl } from '@/lib/classic'
import { cn } from '@/lib/utils'
import { useNodeContext } from '@/nodes/context'
import { useFullValue, type Fetcher } from './expand'
import { LazyJsonView as JsonView } from './lazy'
import { sizeLabel } from './tree'

const KEY_PREVIEW = 8

type Props = { summary: NonNullable<NodeSummary>; expandPath: string | null | undefined; label?: string; compact?: boolean; fetcher?: Fetcher }

export function JsonSummary({ summary, expandPath, label = 'JSON', compact, fetcher }: Props) {
  const { state, load, hide } = useFullValue(expandPath, fetcher)
  const { resource, id } = useNodeContext()
  const { pathname } = useLocation()
  const noteId = useId()
  const kind = summary.kind ?? 'object'
  const size = sizeLabel(kind, summary.size ?? summary.keys?.length ?? 0)
  const keys = summary.keys ?? []

  if (state.status === 'loaded') {
    return (
      <div className="flex min-w-0 max-w-full flex-1 flex-col gap-2">
        <JsonView value={state.value} label={label} maxHeight={compact ? '20rem' : '32rem'} />
        <Button type="button" variant="ghost" size="xs" className="self-start" onClick={hide}>
          <EyeOff />
          Hide value
        </Button>
      </div>
    )
  }

  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      <div className="flex flex-wrap items-center gap-1.5 text-xs">
        <Badge variant="secondary" className="font-mono">
          {kind}
        </Badge>
        {size && <span className="text-muted-foreground">{size}</span>}
        {keys.slice(0, KEY_PREVIEW).map((key) => (
          <code key={key} className="rounded-sm bg-muted px-1.5 py-0.5 font-mono text-muted-foreground">
            {key}
          </code>
        ))}
        {keys.length > KEY_PREVIEW && <span className="text-muted-foreground">+{keys.length - KEY_PREVIEW} more</span>}
      </div>
      {expandPath && !(state.status === 'error' && state.forbidden) && (
        <div className="flex flex-wrap items-center gap-2">
          <Button type="button" variant="outline" size="xs" onClick={load} disabled={state.status === 'loading'} aria-describedby={noteId}>
            {state.status === 'loading' ? <LoaderCircle className="animate-spin motion-reduce:animate-none" /> : <Eye />}
            {state.status === 'loading' ? 'Loading' : state.status === 'error' ? 'Try again' : 'Show full value'}
          </Button>
          <span id={noteId} className={cn('text-xs text-muted-foreground', compact && 'sr-only')}>
            Viewing is recorded in the audit log.
          </span>
        </div>
      )}
      {!expandPath && (
        <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
          <span>Full value available in the classic admin</span>
          <a href={resource ? classicUrl(resource, id) : classicHere(pathname)} className="inline-flex items-center gap-1 text-foreground underline-offset-4 hover:underline">
            Open in classic admin
            <ExternalLink className="size-3" aria-hidden />
          </a>
        </div>
      )}
      {state.status === 'loading' && (
        <span role="status" className="sr-only">
          Loading value
        </span>
      )}
      {state.status === 'error' && (
        <Alert variant="destructive" className="max-w-md">
          <TriangleAlert aria-hidden />
          <AlertDescription className="text-danger">{state.forbidden ? "You don't have access to this value." : "Couldn't load the value. Try again."}</AlertDescription>
        </Alert>
      )}
    </div>
  )
}
