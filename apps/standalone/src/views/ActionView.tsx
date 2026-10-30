import { useEffect, useEffectEvent, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { toast } from 'sonner'
import { apiFetch, errorMessage } from '@/api/fetcher'
import type { Action, ActionResult, FormResponse, PageResponse } from '@/api/generated/model'
import { FormSkeleton } from '@/components/FormSkeleton'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { FormDialog } from '@/forms/FormDialog'
import { entriesToSearch, withSearch } from '@/forms/query'
import { RecordForm, SubmitButton } from '@/forms/RecordForm'
import { saveRecord } from '@/forms/save'
import { useRecordForm } from '@/forms/useRecordForm'
import { FrameBoundary } from '@/boundaries/FrameBoundary'
import { FrameView } from '@/frame/FrameView'
import { IframeView } from '@/frame/IframeView'
import { NodeContext, OwnFormContext, ViewQueryContext, useViewQuery } from '@/nodes/context'
import { NodeList } from '@/nodes/Node'
import { customPages } from './customPages'
import { presentationOf } from './presentation'

type Container = 'page' | 'dialog' | 'sheet'

type BodyProps = {
  action: Action
  resource?: string
  id?: string
  container: Container
  onResult: (result: ActionResult) => void
  onClose: () => void
}

// A write that renders its template again (a search) answers with the page as a FormResponse, not an ActionResult.
type Sent = ActionResult | FormResponse

const isPage = (result: Sent): result is FormResponse => 'form' in result && 'action' in result

// A template with a form answers a FormResponse; a read-only one answers its content as a PageResponse.
type Answer = FormResponse | PageResponse

const isForm = (answer: Answer): answer is FormResponse => 'form' in answer

const send = (response: FormResponse) => (entries: Parameters<typeof saveRecord>[1]) => saveRecord(response, entries) as Promise<Sent>

type PageFormProps = {
  response: FormResponse
  label: string
  classicHref?: string
  ctx: { resource?: string; id?: string }
  onResult: (result: Sent) => void
  onClose: () => void
}

function Content({ nodes, ctx }: { nodes: PageResponse['layout']; ctx: { resource?: string; id?: string } }) {
  return (
    <NodeContext.Provider value={ctx}>
      <div className="flex flex-col gap-4">
        <NodeList nodes={nodes} />
      </div>
    </NodeContext.Provider>
  )
}

// The form, with the rest of the template around it when the response has a layout.
function PageForm({ response, label, classicHref, ctx, onResult, onClose }: PageFormProps) {
  const form = useRecordForm(response, { classicHref })
  const { setSearch } = useViewQuery()
  const submit =
    response.action.method === 'get' ? form.submit(async (entries) => setSearch(entriesToSearch(entries)), () => {}) : form.submit(send(response), onResult)
  const own = (
    <RecordForm form={form} onSubmit={submit}>
      <div className="flex items-center justify-end gap-2">
        <Button type="button" variant="outline" onClick={onClose}>
          Cancel
        </Button>
        <SubmitButton form={form} label={label} pendingLabel="Working…" />
      </div>
    </RecordForm>
  )
  if (!response.layout) return own
  return (
    <OwnFormContext.Provider value={own}>
      <Content nodes={response.layout} ctx={ctx} />
    </OwnFormContext.Provider>
  )
}

// `native`: the action's template was Formtastic-only, so its path answers with a FormResponse (or, with no form at
// all, a PageResponse). What a search sends back is shown in its place until the page refetches (after a row action,
// say), as classic redirects to the form.
function NativeView({ action, path, container, resource, id, onResult, onClose }: BodyProps & { path: string }) {
  // A GET form replaces the view's query: in the address bar on a page, in this view's own state in an overlay.
  const routed = useViewQuery()
  const [held, setHeld] = useState('')
  const query = container === 'page' ? routed : { search: held, setSearch: setHeld }
  const { data, error, dataUpdatedAt: updatedAt, isFetching, isPlaceholderData } = useQuery({
    // Under the resource's prefix, so the writes of this page's actions refetch it.
    queryKey: [`/admin/${resource ?? '_'}/action-form`, path, query.search],
    queryFn: () => apiFetch<Answer>(withSearch(path, query.search)),
    // The page stays up while a new query loads, but another action's page never stands in for this one.
    placeholderData: (previous, previousQuery) => (previousQuery?.queryKey[1] === path ? previous : undefined),
    gcTime: 0,
    staleTime: 0,
    retry: false,
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  })
  // What stands in while a new query loads is the answer it replaces: the form keeps what was typed until the new one arrives.
  const [dataUpdatedAt, setStamp] = useState(updatedAt)
  if (!isPlaceholderData && dataUpdatedAt !== updatedAt) setStamp(updatedAt)
  const [answer, setAnswer] = useState<{ response: FormResponse; at: number; count: number }>()

  const fail = useEffectEvent((cause: Error) => {
    toast.error(errorMessage(cause))
    onClose()
  })
  useEffect(() => {
    if (error) fail(error)
  }, [error])

  const current = answer?.at === dataUpdatedAt ? answer : undefined
  const shown = current?.response ?? data
  const key = `${dataUpdatedAt}-${current?.count ?? 0}`
  const sent = (result: Sent) => (isPage(result) ? setAnswer({ response: result, at: dataUpdatedAt, count: (current?.count ?? 0) + 1 }) : onResult(result))
  const classicHref = action.href ?? undefined
  const ctx = { resource, id }
  const label = (shown && isForm(shown) && shown.submit_label) || action.label
  const page =
    shown &&
    (isForm(shown) ? (
      <PageForm key={key} response={shown} label={label} classicHref={classicHref} ctx={ctx} onResult={sent} onClose={onClose} />
    ) : (
      <Content nodes={shown.layout} ctx={ctx} />
    ))

  const view = (body: React.ReactNode) => <ViewQueryContext value={query}>{body}</ViewQueryContext>

  if (container === 'page')
    return view(
      page ? (
        <div aria-busy={isFetching} className="contents">
          {page}
        </div>
      ) : (
        <FormSkeleton />
      ),
    )
  if (!shown) return null
  // Results need more room than a short form's dialog gives them, and a filter form is shown with its results.
  if (!isForm(shown) || shown.layout || shown.action.method === 'get')
    return view(
      <Dialog open onOpenChange={(open) => !open && onClose()}>
        <DialogContent aria-busy={isFetching} className="max-h-[90dvh] gap-4 overflow-y-auto sm:max-w-5xl">
          <DialogHeader>
            <DialogTitle>{shown.title || action.label}</DialogTitle>
            <DialogDescription className="sr-only">{shown.title || action.label}</DialogDescription>
          </DialogHeader>
          {page}
        </DialogContent>
      </Dialog>,
    )
  return <FormDialog key={key} open response={shown} submitLabel={label} send={send(shown)} onDone={sent} onClose={onClose} classicHref={classicHref} />
}

// One container per ladder mode; pages, dialogs and sheets differ only in chrome.
export function ActionViewBody(props: BodyProps) {
  const { action, resource, id, container, onClose } = props
  const view = action.view
  const path = view?.path ?? action.href ?? undefined
  const bare = container !== 'page'
  if (!view) return null
  if (view.mode === 'native' && view.path) return <NativeView {...props} path={view.path} />
  if (view.mode === 'iframe' && path) return <IframeView src={path} title={action.label} bare={bare} onLeave={onClose} />
  const Custom = view.mode === 'custom' && view.custom_key ? customPages[view.custom_key] : undefined
  if (Custom) return <Custom action={action} resource={resource} id={id} onClose={onClose} />
  // `custom` without a registered component falls back to the classic page.
  return (
    <FrameBoundary src={path} title={action.label}>
      <FrameView src={path} title={action.label} bare={bare} autoFocus onLeave={onClose} />
    </FrameBoundary>
  )
}

type OverlayProps = { action: Action; ctx: { resource?: string; id?: string }; onResult: BodyProps['onResult']; onClose: () => void }

export function ActionViewOverlay({ action, ctx, onResult, onClose }: OverlayProps) {
  const presentation = presentationOf(action)
  const sheet = presentation !== 'dialog' && action.view?.mode !== 'native'
  const body = <ActionViewBody action={action} {...ctx} container={sheet ? 'sheet' : 'dialog'} onResult={onResult} onClose={onClose} />
  if (action.view?.mode === 'native') return body
  if (!sheet)
    return (
      <Dialog open onOpenChange={(open) => !open && onClose()}>
        <DialogContent className="max-h-[90dvh] gap-4 overflow-y-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>{action.label}</DialogTitle>
            <DialogDescription className="sr-only">{action.label}</DialogDescription>
          </DialogHeader>
          {body}
        </DialogContent>
      </Dialog>
    )
  return (
    <Sheet open onOpenChange={(open) => !open && onClose()}>
      <SheetContent side="right" className="w-[min(44rem,calc(100vw-3rem))] gap-0 overflow-y-auto p-0">
        <SheetHeader>
          <SheetTitle>{action.label}</SheetTitle>
          <SheetDescription className="sr-only">{action.label}</SheetDescription>
        </SheetHeader>
        <div className="p-4">{body}</div>
      </SheetContent>
    </Sheet>
  )
}
