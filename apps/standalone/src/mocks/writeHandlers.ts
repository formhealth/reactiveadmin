import { delay, http, HttpResponse } from 'msw'
import type { ActionResult, FormResponse, ValidationError, WriteResult } from '@/api/generated/model'
import { approveForm, approvals } from './domain'
import { posts, type Post } from './fixtures'
import { CSRF_TOKEN, postForm, optionPools, deskForm, desks, rescheduleForm, session } from './forms'

const error = (status: number, code: string, message: string) => HttpResponse.json({ code, message }, { status })

const invalid = (errors: Record<string, string[]> = {}, base: string[] = []) =>
  HttpResponse.json({ code: 'invalid', message: 'Review failed', errors, base } satisfies ValidationError, { status: 422 })

const badToken = (request: Request) =>
  request.headers.get('x-csrf-token') === CSRF_TOKEN ? undefined : error(422, 'invalid_csrf', 'Your session expired. Try again.')

const find = (id: string) => posts.find((e) => String(e.id) === id)

type Params = Record<string, unknown>

const postErrors = (p: Params) => {
  const errors: Record<string, string[]> = {}
  const details = p.details as Params | string | null | undefined
  if (!p.published_on) errors.published_on = ["can't be blank"]
  if (!p.editor_id) errors.editor = ['must exist']
  if (p.embargo_until && p.published_on && String(p.embargo_until) < String(p.published_on)) errors.embargo_until = ['must be on or after the date of service']
  if (typeof details === 'string') errors.details = ['must be a JSON object']
  else if (details?.author_state && !/^[A-Z]{2}$/.test(String(details.author_state))) errors.details = ['author_state must be a two-letter code']
  return errors
}

const written = (resource: string, id: string, message: string, view: 'show' | 'index' = 'show'): WriteResult => ({
  ok: true,
  id,
  message,
  location: { url: `/admin/${resource}${view === 'show' ? `/${id}` : ''}`, resource, id, view },
})

const memberAction = (e: Post, action: string): ActionResult | undefined =>
  ({
    retry_publication: { ok: true as const, message: `Retry queued for post #${e.id}` },
    lift_embargo: { ok: true as const, message: `Embargo lifted for post #${e.id}`, location: { url: `/admin/posts/${e.id}`, resource: 'posts', id: String(e.id), view: 'show' as const } },
  })[action]

const batchMessages: Record<string, (n: number) => string> = {
  lift_embargo: (n) => `Lifted ${n} ${n === 1 ? 'embargo' : 'embargoes'}`,
  set_embargo: (n) => `Updated embargo date for ${n} ${n === 1 ? 'post' : 'posts'}`,
  destroy: (n) => `Deleted ${n} ${n === 1 ? 'post' : 'posts'}`,
}

export const writeHandlers = [
  http.get('/api/admin/_session', () => HttpResponse.json(session)),

  http.get('/api/admin/:resource/new', async ({ params }) => {
    await delay(200)
    const body: FormResponse | undefined = params.resource === 'posts' ? postForm() : params.resource === 'desks' ? deskForm() : undefined
    return body ? HttpResponse.json(body) : error(404, 'not_found', 'Form not found')
  }),

  http.get('/api/admin/:resource/_options', async ({ request }) => {
    await delay(250)
    const sp = new URL(request.url).searchParams
    const pool = optionPools[sp.get('field') ?? '']
    if (!pool) return error(404, 'not_found', 'Unknown field')
    const values = sp.get('value')?.split(',')
    const term = (sp.get('term') ?? '').toLowerCase()
    const matches = values
      ? pool.filter((o) => values.includes(o.value))
      : pool.filter((o) => o.value === term || o.label.toLowerCase().split(/\s+/).some((word) => word.startsWith(term)) || o.label.toLowerCase().startsWith(term))
    const limit = Number(sp.get('limit')) || 10
    const start = Number(sp.get('cursor') ?? 0)
    const more = matches.length > start + limit
    return HttpResponse.json({ options: matches.slice(start, start + limit), truncated: more, next_cursor: more ? String(start + limit) : null })
  }),

  // Batched labels for selected values; without it a saved id shows as its raw number.
  http.get('/api/admin/:resource/_options/lookup', async ({ request }) => {
    await delay(250)
    const lookups = Object.fromEntries(
      [...new URL(request.url).searchParams]
        .filter(([key]) => key.startsWith('fields['))
        .map(([key, values]) => {
          const pool = optionPools[key.slice(7, -1)] ?? []
          return [key.slice(7, -1), pool.filter((o) => values.split(',').includes(o.value))]
        }),
    )
    return HttpResponse.json({ lookups })
  }),

  http.get('/api/admin/:resource/:id/:action', async ({ params }) => {
    await delay(200)
    const { resource, id, action } = params as Record<string, string>
    const post = find(id)
    if (resource === 'posts' && post) {
      if (action === 'edit') return HttpResponse.json(postForm(post))
      if (action === 'reschedule_embargo') return HttpResponse.json(rescheduleForm(post))
    }
    const priorAuth = approvals.find((pa) => pa.id === id)
    if (resource === 'content_approvals' && priorAuth && action === 'approve') return HttpResponse.json(approveForm(priorAuth))
    const desk = desks.find((p) => p.id === id)
    if (resource === 'desks' && desk && action === 'edit') return HttpResponse.json(deskForm(desk))
    return error(404, 'not_found', 'Record not found')
  }),

  http.post('/api/admin/:resource/batch_action', async ({ request }) => {
    await delay(300)
    const rejected = badToken(request)
    if (rejected) return rejected
    const { batch_action, collection_selection, batch_action_inputs } = (await request.json()) as {
      batch_action: string
      collection_selection: string[]
      batch_action_inputs?: Params
    }
    if (batch_action === 'set_embargo' && !batch_action_inputs?.embargo_until) return invalid({ embargo_until: ["can't be blank"] })
    return HttpResponse.json({ ok: true, message: batchMessages[batch_action]?.(collection_selection.length) ?? 'Done' } satisfies ActionResult)
  }),

  // Collection actions: `POST /admin/{resource}/{action}` with no record.
  http.post('/api/admin/:resource/:action', async ({ params, request }) => {
    await delay(300)
    const rejected = badToken(request)
    if (rejected) return rejected
    const message = { publish_pending: 'Published 14 pending posts', sync_publisher: 'Publisher sync queued' }[String(params.action)]
    return message ? HttpResponse.json({ ok: true, message } satisfies ActionResult) : error(404, 'not_found', 'Unknown action')
  }),

  http.post('/api/admin/:resource/:id/:action', async ({ params, request }) => {
    await delay(300)
    const rejected = badToken(request)
    if (rejected) return rejected
    const { resource, id, action } = params as Record<string, string>
    if (resource === 'authors' && action === 'resend_welcome') return HttpResponse.json({ ok: true, message: 'Welcome email sent' } satisfies ActionResult)
    if (resource === 'content_approvals' && action === 'approve') {
      const body = (await request.json()) as Record<string, Params>
      if (!body.approval?.reference_number) return invalid({ reference_number: ["can't be blank"] })
      const location = { url: `/admin/${resource}/${id}`, resource, id, view: 'show' as const }
      return HttpResponse.json({ ok: true, message: `Prior authorization #${id} approved`, location } satisfies ActionResult)
    }
    const post = find(id)
    if (!post) return error(404, 'not_found', 'Record not found')
    if (action === 'reschedule_embargo') {
      const body = (await request.json()) as Params
      return body.embargo_until ? HttpResponse.json({ ok: true, message: `Embargo rescheduled to ${body.embargo_until}` } satisfies ActionResult) : invalid({ embargo_until: ["can't be blank"] })
    }
    const result = memberAction(post, action)
    return result ? HttpResponse.json(result) : error(404, 'not_found', 'Unknown action')
  }),

  http.post('/api/admin/:resource', async ({ params, request }) => {
    await delay(400)
    const rejected = badToken(request)
    if (rejected) return rejected
    const body = (await request.json()) as Record<string, Params>
    if (params.resource === 'desks') {
      const emails = Object.values((body.desk?.desk_members_attributes ?? {}) as Record<string, Params>).map((u) => u.user_email)
      if (!body.desk?.name) return invalid({ name: ["can't be blank"] })
      if (emails.includes('taken@example.com')) return invalid({ 'desk_members.user_email': ['is already a member of another desk'] })
      return HttpResponse.json(written('desks', 'desk-3', 'Desk was successfully created.', 'index'), { status: 201 })
    }
    const errors = postErrors(body.post ?? {})
    if (Object.keys(errors).length) return invalid(errors)
    return HttpResponse.json(written('posts', String(posts[0].id), 'post was successfully created.'), { status: 201 })
  }),

  http.patch('/api/admin/:resource/:id', async ({ params, request }) => {
    await delay(400)
    const rejected = badToken(request)
    if (rejected) return rejected
    const id = String(params.id)
    const body = (await request.json()) as Record<string, Params>
    if (params.resource === 'desks') return HttpResponse.json(written('desks', id, 'Desk was successfully updated.', 'index'))
    if (!find(id)) return error(404, 'not_found', 'Record not found')
    const errors = postErrors(body.post ?? {})
    if (Object.keys(errors).length) return invalid(errors, ['post could not be saved'])
    return HttpResponse.json(written('posts', id, 'post was successfully updated.'))
  }),

  http.delete('/api/admin/:resource/:id', async ({ params, request }) => {
    await delay(300)
    const rejected = badToken(request)
    if (rejected) return rejected
    const id = String(params.id)
    return find(id) ? HttpResponse.json(written('posts', id, 'post was successfully destroyed.', 'index')) : error(404, 'not_found', 'Record not found')
  }),
]
