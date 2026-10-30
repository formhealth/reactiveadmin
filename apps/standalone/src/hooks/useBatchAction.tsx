import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { runBatchAction } from '@/api/generated/core'
import type { BatchAction, FormResponse } from '@/api/generated/model'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { LazyFormDialog } from '@/forms/lazy'
import { toastError } from '@/lib/apiDenied'
import { invalidateResource } from '@/lib/records'

const plural = (n: number) => `${n} ${n === 1 ? 'record' : 'records'}`

export const batchForm = (resource: string, action: BatchAction): FormResponse => ({
  resource,
  title: action.label,
  action: { method: 'post', path: `/api/admin/${resource}/batch_action` },
  form: { sections: [{ kind: 'inputs', fields: action.inputs }] },
  permissions: {},
})

// Confirms (or collects the action's inputs), posts the selection, then reports the outcome as a toast.
export function useBatchAction(resource: string, ids: string[], onDone: () => void) {
  const queryClient = useQueryClient()
  const [action, setAction] = useState<BatchAction>()
  const close = () => setAction(undefined)

  const send = async (batch: BatchAction, inputs?: Record<string, unknown>) => {
    const result = await runBatchAction(resource, { batch_action: batch.key, collection_selection: ids, batch_action_inputs: inputs })
    toast.success(result.message ?? `${batch.label} applied to ${plural(ids.length)}`)
    invalidateResource(queryClient, resource)
    onDone()
    return result
  }

  const confirmed = async (batch: BatchAction) => {
    try {
      await send(batch)
    } catch (error) {
      toastError(error)
    }
  }

  const dialogs = action && (
    <>
      {action.inputs.length === 0 ? (
        <AlertDialog open onOpenChange={(open) => !open && close()}>
          <AlertDialogContent>
            <AlertDialogTitle>{action.label}</AlertDialogTitle>
            <AlertDialogDescription>{action.confirm ?? `Run "${action.label}" on ${plural(ids.length)}?`}</AlertDialogDescription>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction variant={action.key === 'destroy' ? 'destructive' : 'default'} onClick={() => confirmed(action)}>
                {action.label}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      ) : (
        <LazyFormDialog
          open
          response={batchForm(resource, action)}
          description={action.confirm ?? `Applies to ${plural(ids.length)}.`}
          submitLabel={action.label}
          send={(entries) => {
            const names = new Map(action.inputs.map((f) => [f.param, f.name]))
            return send(action, Object.fromEntries(entries.map(([param, value]) => [names.get(param) ?? param, value])))
          }}
          onDone={close}
          onClose={close}
        />
      )}
    </>
  )

  return { run: setAction, dialogs }
}
