import { useMemo, useState } from 'react'
import { apiFetch, errorMessage } from '@/api/fetcher'
import type { FormResponse } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Skeleton } from '@/components/ui/skeleton'
import type { FormValues } from './model'
import { reviewStale, type Change } from './stale'
import type { RecordFormApi } from './useRecordForm'

type Props = {
  form: RecordFormApi
  // Swaps in the freshly loaded form; `carry` is what to re-apply on top of it.
  onRebase: (fresh: FormResponse, carry?: FormValues) => void
}

type Phase = 'prompt' | 'review' | 'error'

function ChangeRow({ change }: { change: Change }) {
  return (
    <li className="rounded-md border p-3">
      <p className="text-sm font-medium">
        {change.label}
        {change.conflict && <span className="ml-2 text-xs font-normal text-warning">Also changed by someone else</span>}
      </p>
      <dl className="mt-2 grid gap-2 text-sm sm:grid-cols-2">
        <div className="min-w-0">
          <dt className="text-xs text-muted-foreground">Latest saved</dt>
          <dd className="break-words">{change.server}</dd>
        </div>
        <div className="min-w-0 rounded-sm bg-primary/5 px-2 py-1 sm:-my-1">
          <dt className="text-xs text-muted-foreground">Your edit</dt>
          <dd className="break-words">{change.yours}</dd>
        </div>
      </dl>
    </li>
  )
}

// A write was rejected because the record changed after the form loaded. Nothing is sent again from here:
// you either look at the differences and re-apply your edits to the latest version, or start over from it.
export function StaleDialog({ form, onRebase }: Props) {
  const [phase, setPhase] = useState<Phase>('prompt')
  const [busy, setBusy] = useState<'review' | 'discard'>()
  const [fresh, setFresh] = useState<FormResponse>()
  const [failure, setFailure] = useState('')
  const review = useMemo(() => fresh && reviewStale(form.response, fresh, form.methods.getValues()), [fresh, form])
  const hasRows = form.sections.some((s) => s.kind === 'has_many')

  const load = async (mode: 'review' | 'discard') => {
    setBusy(mode)
    try {
      const latest = await apiFetch<FormResponse>(`${form.response.action.path}/edit`)
      if (mode === 'discard') return onRebase(latest)
      setFresh(latest)
      setPhase('review')
    } catch (error) {
      setFailure(errorMessage(error))
      setPhase('error')
    } finally {
      setBusy(undefined)
    }
  }

  const discard = (
    <Button variant="outline" disabled={!!busy} onClick={() => (fresh ? onRebase(fresh) : load('discard'))}>
      {busy === 'discard' ? 'Reloading…' : 'Discard my changes'}
    </Button>
  )

  return (
    <Dialog open onOpenChange={(open) => !open && form.setStale(false)}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-xl">
        {phase === 'review' && review ? (
          <>
            <DialogHeader>
              <DialogTitle>Review changes</DialogTitle>
              <DialogDescription>
                {review.changes.length
                  ? 'Your edits are compared with the latest saved version. Re-applying keeps your values and leaves everything else as it is now.'
                  : 'The latest saved version already has your edits, or nothing you changed differs from it.'}
              </DialogDescription>
            </DialogHeader>
            {review.changes.length > 0 && (
              <ul className="flex flex-col gap-2">
                {review.changes.map((change) => (
                  <ChangeRow key={change.key} change={change} />
                ))}
              </ul>
            )}
            {review.theirs.length > 0 && <p className="text-sm text-muted-foreground">Also changed by someone else, and kept as saved: {review.theirs.join(', ')}.</p>}
            {hasRows && <p className="text-sm text-muted-foreground">Changes to rows in lists aren't compared. Check them again after re-applying.</p>}
            <DialogFooter>
              {discard}
              <Button autoFocus disabled={!!busy} onClick={() => onRebase(fresh!, review.carry)}>
                {review.changes.length ? 'Re-apply my changes' : 'Load latest version'}
              </Button>
            </DialogFooter>
          </>
        ) : (
          <>
            <DialogHeader>
              <DialogTitle>This record changed since you opened it</DialogTitle>
              <DialogDescription>Someone else saved it while you were editing, so your changes weren't saved. Nothing was overwritten.</DialogDescription>
            </DialogHeader>
            {phase === 'error' && (
              <p role="alert" className="text-sm text-danger">
                Couldn't load the latest version: {failure}. Try again.
              </p>
            )}
            {busy === 'review' && <Skeleton className="h-10 w-full" />}
            <DialogFooter>
              {discard}
              <Button autoFocus disabled={!!busy} onClick={() => load('review')}>
                {busy === 'review' ? 'Loading…' : 'Review changes'}
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
