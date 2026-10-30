import { useQueryClient } from '@tanstack/react-query'
import { useLocation, useNavigate } from 'react-router'
import { toast } from 'sonner'
import type { ActionResult, FormResponse } from '@/api/generated/model'
import type { Entry } from '@/forms/params'
import { entriesToSearch } from '@/forms/query'
import { RecordForm, SubmitButton } from '@/forms/RecordForm'
import { saveRecord } from '@/forms/save'
import { useRecordForm } from '@/forms/useRecordForm'
import { useMapClassic } from '@/hooks/useManifest'
import { adminPath } from '@/lib/base'
import { sameOrigin, withClassic } from '@/lib/classic'
import { follow, invalidateData, routeFor } from '@/lib/records'
import { useViewQuery } from './context'

export function InlineForm({ response, onDone }: { response: FormResponse; onDone: () => void }) {
  const form = useRecordForm(response, { classicHref: withClassic(`${adminPath}/${response.resource}`) })
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const queryClient = useQueryClient()
  const mapUrl = useMapClassic()
  const label = response.submit_label || 'Submit'

  const send = (entries: Entry[]) => saveRecord(response, entries) as Promise<ActionResult>

  // Like a page action in the classic admin: the page it redirects to is shown again, a redirect elsewhere is followed.
  const sent = (result: ActionResult) => {
    const { location } = result
    toast.success(result.message ?? `${label} done`)
    invalidateData(queryClient)
    const target = location && (routeFor(location) || (location.url ? mapUrl(location.url) : undefined))
    const stays = !location || target === pathname || (location.url && sameOrigin(location.url)?.pathname === `${adminPath}/${response.resource}`)
    if (!stays) follow(navigate, location, pathname, mapUrl)
    onDone()
  }

  const { setSearch } = useViewQuery()
  const submit =
    response.action.method === 'get' ? form.submit(async (entries) => setSearch(entriesToSearch(entries)), () => {}) : form.submit(send, sent)

  return (
    <div className="flex flex-col gap-3">
      {response.title && <h3 className="text-base font-semibold">{response.title}</h3>}
      <RecordForm form={form} plain onSubmit={submit}>
        <div>
          <SubmitButton form={form} label={label} pendingLabel="Working…" />
        </div>
      </RecordForm>
    </div>
  )
}
