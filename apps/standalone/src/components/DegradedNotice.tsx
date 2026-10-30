import { useEffect, useState } from 'react'
import { ChevronDown, ExternalLink, Info, X } from 'lucide-react'
import { toast } from 'sonner'
import type { Degradation } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

const signatureOf = (degraded: Degradation[]) => degraded.map((d) => `${d.kind}@${d.where ?? ''}`).join('|')

const sentence = (text: string) => text.charAt(0).toUpperCase() + text.slice(1) + (/[.!?]$/.test(text) ? '' : '.')

// The server couldn't show everything faithfully. Quiet on purpose: content is never blocked, and the way
// out (classic admin) is one click away.
export function DegradedNotice({ degraded, classicHref }: { degraded?: Degradation[]; classicHref?: string }) {
  const [dismissed, setDismissed] = useState<string>()
  const [open, setOpen] = useState(false)
  const signature = degraded?.length ? signatureOf(degraded) : ''

  useEffect(() => {
    if (!import.meta.env.DEV || !degraded?.length) return
    toast.info('Degraded response (dev only)', {
      id: `degraded:${signature}`,
      description: degraded.map((d) => (d.where ? `${d.kind} at ${d.where}` : d.kind)).join('\n'),
      style: { whiteSpace: 'pre-line' },
    })
  }, [degraded, signature])

  if (!degraded?.length || dismissed === signature) return null
  const reasons = [...new Set(degraded.map((d) => sentence(d.reason)))]

  return (
    <div role="status" data-slot="degraded-notice" className="rounded-lg border bg-muted/40 px-3 py-2 text-sm">
      <div className="flex items-start gap-2.5">
        <Info className="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden />
        <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-3 gap-y-1">
          <p className="text-muted-foreground">Some parts of this page are shown in a simplified form.</p>
          {classicHref && (
            <a href={classicHref} className="inline-flex items-center gap-1 whitespace-nowrap underline decoration-muted-foreground/50 underline-offset-4 hover:decoration-foreground">
              Open in classic admin
              <ExternalLink className="size-3" aria-hidden />
            </a>
          )}
          <button
            type="button"
            aria-expanded={open}
            onClick={() => setOpen(!open)}
            className="inline-flex items-center gap-0.5 rounded-sm text-muted-foreground outline-none hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
          >
            {open ? 'Hide details' : 'What changed?'}
            <ChevronDown className={cn('size-3.5 transition-transform motion-reduce:transition-none', open && 'rotate-180')} aria-hidden />
          </button>
        </div>
        <Button variant="ghost" size="icon-xs" aria-label="Dismiss" onClick={() => setDismissed(signature)}>
          <X />
        </Button>
      </div>
      {open && (
        <ul className="mt-2 flex list-disc flex-col gap-1 pl-[1.625rem] text-muted-foreground marker:text-muted-foreground/60">
          {reasons.map((reason) => (
            <li key={reason}>{reason}</li>
          ))}
        </ul>
      )}
    </div>
  )
}
