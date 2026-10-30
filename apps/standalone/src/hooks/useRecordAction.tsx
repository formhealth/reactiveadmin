import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { toast } from 'sonner'
import { apiFetch } from '@/api/fetcher'
import type { Action, ActionResult, FormResponse } from '@/api/generated/model'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { LazyActionViewOverlay, LazyFormDialog } from '@/forms/lazy'
import { saveRecord } from '@/forms/save'
import { useMapClassic } from '@/hooks/useManifest'
import { planOf } from '@/lib/actions'
import { classicUrl, withClassic } from '@/lib/classic'
import { submitNavigation } from '@/lib/navigate'
import { toastError } from '@/lib/apiDenied'
import { follow, invalidateData, invalidateResource } from '@/lib/records'
import { presentationOf } from '@/views/presentation'

// Where an action runs: a record (`resource` and `id`), a resource's collection, or a page (neither).
export type ActionContext = { resource?: string; id?: string; name?: string | null }

export const viewRoute = ({ resource, id }: ActionContext, key: string) => `/${resource}/${id ? `${id}/` : ''}actions/${key}`

// Toast, refetch and follow-the-redirect once an action succeeded.
export function useActionDone({ resource, id, name }: ActionContext) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const mapUrl = useMapClassic()

  return (action: Action, result: ActionResult) => {
    toast.success(action.kind === 'destroy' && name ? `${name} deleted` : (result.message ?? `${action.label} done`))
    if (resource) invalidateResource(queryClient, resource)
    else invalidateData(queryClient)
    const { location } = result
    const staysHere = !!resource && location?.resource === resource && location.id === id && location.view !== 'edit'
    if (action.kind === 'destroy' || (location && !staysHere)) follow(navigate, location, resource ? `/${resource}` : '/', mapUrl)
  }
}

// The single place actions run: edit, destroy, member and collection actions, forms to fill in, the fallback
// ladder's views, and classic fallbacks.
export function useRecordAction(ctx: ActionContext = {}) {
  const { resource, id } = ctx
  const navigate = useNavigate()
  const done = useActionDone(ctx)
  const [pending, setPending] = useState<Action>()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<{ action: Action; response: FormResponse }>()
  const [view, setView] = useState<Action>()

  const classic = (action: Action) => {
    if ((action.method ?? 'get') === 'get' && action.href) return window.location.assign(withClassic(action.href))
    if (resource && id) window.open(classicUrl(resource, id), '_blank', 'noopener')
    toast.info(`Finish "${action.label}" in the classic admin`, { description: "Changes can't be made from here yet." })
  }

  const openForm = async (action: Action, path: string) => {
    try {
      const response = await apiFetch<FormResponse>(path)
      if (response.form) setForm({ action, response })
      else toast.error(`"${action.label}" can't be opened here`)
    } catch (error) {
      toastError(error)
    }
  }

  // Pages need a resource to route under; elsewhere (page actions, inline nodes) the view opens as an overlay.
  const openView = (action: Action) =>
    presentationOf(action) === 'page' && resource ? navigate(viewRoute(ctx, action.key), { state: { action } }) : setView(action)

  const execute = async (action: Action) => {
    const plan = planOf(action)
    if (plan === 'none') return
    if (plan === 'navigate') return submitNavigation(action).catch(toastError)
    if (plan === 'edit') return resource && id ? navigate(`/${resource}/${id}/edit`) : undefined
    if (plan === 'view') return openView(action)
    if (plan === 'external') return void window.open(action.href!, '_blank', 'noopener,noreferrer')
    if (plan === 'form') return openForm(action, action.form_path!)
    if (plan === 'classic') return classic(action)
    try {
      done(action, await apiFetch<ActionResult>(action.api_path!, { method: (action.method ?? 'get').toUpperCase() }))
    } catch (error) {
      toastError(error)
    }
  }

  const request = (action: Action) => {
    if (!action.confirm && action.kind !== 'destroy') return execute(action)
    setPending(action)
    setOpen(true)
  }

  const dialogs = (
    <>
      <AlertDialog open={open} onOpenChange={setOpen}>
        <AlertDialogContent>
          <AlertDialogTitle>{pending?.label}</AlertDialogTitle>
          <AlertDialogDescription>{pending?.confirm ?? "This can't be undone."}</AlertDialogDescription>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction variant={pending?.kind === 'destroy' ? 'destructive' : 'default'} onClick={() => pending && execute(pending)}>
              {pending?.label}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      {form && (
        <LazyFormDialog
          open
          response={form.response}
          submitLabel={form.action.label}
          classicHref={form.action.href ?? undefined}
          send={(entries) => saveRecord(form.response, entries) as Promise<ActionResult>}
          onDone={(result) => {
            setForm(undefined)
            done(form.action, result)
          }}
          onClose={() => setForm(undefined)}
        />
      )}
      {view && (
        <LazyActionViewOverlay
          action={view}
          ctx={ctx}
          onResult={(result) => {
            setView(undefined)
            done(view, result)
          }}
          onClose={() => setView(undefined)}
        />
      )}
    </>
  )

  return { request, dialogs }
}
