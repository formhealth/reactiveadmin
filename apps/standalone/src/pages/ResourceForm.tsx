import { useEffect, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Link, useBlocker, useNavigate, useParams } from 'react-router'
import { toast } from 'sonner'
import { ApiError } from '@/api/fetcher'
import { getEditForm, getGetEditFormQueryKey, getNewForm, useGetEditForm, useGetNewForm } from '@/api/generated/core'
import type { FormResponse, ResourceSummary, WriteResult } from '@/api/generated/model'
import { ActionBar } from '@/components/ActionBar'
import { DegradedNotice } from '@/components/DegradedNotice'
import { ErrorState } from '@/components/ErrorState'
import { FormSkeleton } from '@/components/FormSkeleton'
import { PageHeader } from '@/components/PageHeader'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogTitle } from '@/components/ui/alert-dialog'
import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from '@/components/ui/breadcrumb'
import { Button } from '@/components/ui/button'
import type { FormValues } from '@/forms/model'
import { FormStatus, RecordForm, SubmitButton } from '@/forms/RecordForm'
import { saveRecord } from '@/forms/save'
import { StaleDialog } from '@/forms/StaleDialog'
import { useRecordForm } from '@/forms/useRecordForm'
import { ValueRefreshContext } from '@/json/expand'
import { useDocumentTitle, useMapClassic, useResourceSummary } from '@/hooks/useManifest'
import { useRecordVisit } from '@/hooks/useRecordVisit'
import { isUuid, shortId } from '@/lib/ids'
import { follow, invalidateResource } from '@/lib/records'
import { pluralLabel } from '@/lib/humanize'

type Mode = 'new' | 'edit'

export function DiscardDialog({ open, onKeep, onDiscard }: { open: boolean; onKeep: () => void; onDiscard: () => void }) {
  return (
    <AlertDialog open={open} onOpenChange={(next) => !next && onKeep()}>
      <AlertDialogContent>
        <AlertDialogTitle>Discard changes?</AlertDialogTitle>
        <AlertDialogDescription>You have unsaved changes. If you leave now, they'll be lost.</AlertDialogDescription>
        <AlertDialogFooter>
          <AlertDialogCancel>Keep editing</AlertDialogCancel>
          <AlertDialogAction variant="destructive" onClick={onDiscard}>
            Discard changes
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}

type EditorProps = {
  mode: Mode
  response: FormResponse
  summary?: ResourceSummary
  carry?: FormValues
  onRebase: (fresh: FormResponse, carry?: FormValues) => void
}

function FormEditor({ mode, response, summary, carry, onRebase }: EditorProps) {
  const { resource, id, display_name: name } = response
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const mapUrl = useMapClassic()
  const form = useRecordForm(response, { carry })
  const saved = useRef(false)
  const title = mode === 'edit' && name ? `Edit ${name}` : response.title
  useDocumentTitle(title)
  useRecordVisit(!!id, resource, id ?? '')

  const blocker = useBlocker(({ currentLocation, nextLocation }) => form.dirty && !saved.current && currentLocation.pathname !== nextLocation.pathname)

  useEffect(() => {
    if (!form.dirty) return
    const warn = (e: BeforeUnloadEvent) => e.preventDefault()
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [form.dirty])

  const onSaved = (result: WriteResult) => {
    saved.current = true
    toast.success(mode === 'edit' && name ? `${name} updated` : (result.message ?? (mode === 'new' ? 'Created' : 'Saved')))
    invalidateResource(queryClient, resource, 'none')
    follow(navigate, result.location, `/${resource}/${result.id}`, mapUrl)
  }

  const backTo = id ? `/${resource}/${id}` : `/${resource}`
  const label = pluralLabel(summary, resource)

  return (
    <div className="flex flex-col gap-5">
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            <BreadcrumbLink asChild>
              <Link to={`/${resource}`}>{label}</Link>
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          {id && (
            <>
              <BreadcrumbItem>
                <BreadcrumbLink asChild>
                  <Link to={backTo}>{name ?? (isUuid(id) ? `${shortId(id)}…` : `#${id}`)}</Link>
                </BreadcrumbLink>
              </BreadcrumbItem>
              <BreadcrumbSeparator />
            </>
          )}
          <BreadcrumbItem>
            <BreadcrumbPage>{mode === 'new' ? 'New' : 'Edit'}</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>

      <PageHeader title={title}>{response.actions && response.actions.length > 0 && <ActionBar actions={response.actions} ctx={{ resource, id, name }} />}</PageHeader>

      <DegradedNotice degraded={response.degraded} classicHref={form.classicHref} />

      <RecordForm form={form} onSubmit={(event) => form.submit((entries) => saveRecord(response, entries), onSaved)(event)}>
        <div className="sticky bottom-0 z-20 -mx-4 mt-2 -mb-5 flex items-center justify-between gap-3 border-t bg-background px-4 py-3 sm:-mx-6 sm:px-6">
          <FormStatus form={form} />
          <div className="flex items-center gap-2">
            <Button asChild variant="outline">
              <Link to={backTo}>Cancel</Link>
            </Button>
            <SubmitButton form={form} label={mode === 'new' ? `Create ${summary?.label ?? 'record'}` : 'Save changes'} />
          </div>
        </div>
      </RecordForm>

      {form.stale && <StaleDialog form={form} onRebase={onRebase} />}

      <DiscardDialog open={blocker.state === 'blocked'} onKeep={() => blocker.reset?.()} onDiscard={() => blocker.proceed?.()} />
    </div>
  )
}

export function ResourceForm({ mode }: { mode: Mode }) {
  const { resource = '', id = '' } = useParams()
  const { summary } = useResourceSummary(resource)
  const query = { staleTime: Infinity, gcTime: 0, refetchOnWindowFocus: false }
  const edit = useGetEditForm(resource, id, { query: { ...query, enabled: mode === 'edit' } })
  const create = useGetNewForm(resource, { query: { ...query, enabled: mode === 'new' } })
  const { data, error, refetch } = mode === 'edit' ? edit : create
  const queryClient = useQueryClient()
  const [rebased, setRebased] = useState<{ carry?: FormValues; count: number }>({ count: 0 })
  const label = pluralLabel(summary, resource)
  const backTo = { to: id ? `/${resource}/${id}` : `/${resource}`, label: `Back to ${label}` }

  // The editor remounts on the fresh record (and its new lock), so no state from the stale one lingers.
  const rebase = (fresh: FormResponse, carry?: FormValues) => {
    queryClient.setQueryData(getGetEditFormQueryKey(resource, id), fresh)
    setRebased(({ count }) => ({ carry, count: count + 1 }))
  }

  if (error) return <ErrorState error={error} label={label} onRetry={refetch} backTo={backTo} />
  if (mode === 'new' && summary?.permissions.create === false) return <ErrorState error={new ApiError(403)} label={`new ${label}`} />
  if (!data) return <FormSkeleton />

  // Fetched outside the query cache, so a token refresh never replaces what the user is editing.
  const refreshValues = () => (mode === 'edit' ? getEditForm(resource, id) : getNewForm(resource))

  return (
    <ValueRefreshContext value={refreshValues}>
      <FormEditor key={`${data.id ?? 'new'}:${rebased.count}`} mode={mode} response={data} summary={summary} carry={rebased.carry} onRebase={rebase} />
    </ValueRefreshContext>
  )
}
