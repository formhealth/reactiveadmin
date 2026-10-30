import type { BatchAction } from '@/api/generated/model'
import { ClassicLink } from '@/components/ApiDenied'
import { Button } from '@/components/ui/button'

type BatchBarProps = { count: number; actions: BatchAction[]; onRun: (action: BatchAction) => void; onClear: () => void }

export function BatchBar({ count, actions, onRun, onClear }: BatchBarProps) {
  return (
    <div role="region" aria-label="Batch actions" className="sticky top-0 z-40 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border border-primary/40 bg-card px-3 py-2">
      <span className="font-semibold tabular-nums" aria-live="polite">
        {count} selected
      </span>
      <span aria-hidden className="text-muted-foreground">
        ·
      </span>
      <div className="flex flex-wrap items-center gap-2">
        {actions.map((action) =>
          action.api_denied && action.classic_url ? (
            <Button key={action.key} asChild size="sm" variant="outline" title={action.disabled_reason}>
              <ClassicLink href={action.classic_url}>{action.label}</ClassicLink>
            </Button>
          ) : (
            <Button key={action.key} size="sm" variant={action.key === 'destroy' ? 'destructive' : 'outline'} onClick={() => onRun(action)}>
              {action.label}
            </Button>
          ),
        )}
      </div>
      <Button size="sm" variant="ghost" className="ml-auto" onClick={onClear}>
        Clear selection
      </Button>
    </div>
  )
}
