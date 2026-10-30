import { delay, http, HttpResponse } from 'msw'
import type { IndexResponse, Manifest, Scope, ShowResponse } from '@/api/generated/model'
import { classicHandlers } from './classic'
import { attachmentColumns, attachmentRows, pages, authorShow, approvalColumns, approvalRows, approvalShow, approvals } from './domain'
import { deskColumns, deskRows } from './forms'
import { authorColumns, authorRows } from './authors'
import {
  cellsFor,
  columns,
  postActions,
  postName,
  postRowActions,
  posts,
  menu,
  resourceMetas,
  resourceSummaries,
  rowPermissions,
  scopeDefs,
  showLayout,
  site,
  type Post,
} from './fixtures'
import { writeHandlers } from './writeHandlers'

export const apiError = (status: number, code: string, message: string) => HttpResponse.json({ code, message }, { status })

const notFound = () => apiError(404, 'not_found', 'Record not found')

export const manifestBody: Manifest = { schema_version: 2, site, menu, resources: resourceSummaries }

const ransack = [
  ['_gteq', (a: string, b: string) => a >= b],
  ['_lteq', (a: string, b: string) => a <= b],
  ['_eq', (a: string, b: string) => a === b],
] as const

function matchesQuery(e: Post, q: [string, string][]) {
  const raw = e as unknown as Record<string, string | number | null>
  return q.every(([param, value]) => {
    const [suffix, test] = ransack.find(([s]) => param.endsWith(s)) ?? []
    const field = raw[param.slice(0, -(suffix?.length ?? 0))]
    if (!test || field == null) return false
    // created_at carries a time; compare by day so `lteq` includes the end date
    return test(String(field).slice(0, 10), value)
  })
}

const sortRows = (rows: Post[], order?: string | null) => {
  const [, field, dir] = /^(.+)_(asc|desc)$/.exec(order ?? '') ?? []
  if (!field) return rows
  const key = field as keyof Post
  const sign = dir === 'desc' ? -1 : 1
  return [...rows].sort((a, b) => sign * String(a[key] ?? '').localeCompare(String(b[key] ?? ''), undefined, { numeric: true }))
}

const csv = (rows: string[][]) => rows.map((row) => row.join(',')).join('\n')

export const handlers = [
  // Ahead of writeHandlers, whose `/:resource/:id/:action` would otherwise answer this path with a 404.
  http.post('/api/admin/_pages/batch_operations/refresh', async () => {
    await delay(200)
    return HttpResponse.json({ ok: true, message: 'Batch history refreshed' })
  }),
  ...writeHandlers,
  ...classicHandlers,

  http.get('/api/admin/_manifest', async () => {
    await delay(150)
    return HttpResponse.json(manifestBody)
  }),

  http.get('/api/admin/_pages/:page', async ({ params }) => {
    await delay(150)
    const page = pages[String(params.page)]
    return page ? HttpResponse.json(page) : notFound()
  }),

  http.get('/api/admin/:resource/_meta', async ({ params }) => {
    await delay(100)
    const meta = resourceMetas.find((r) => r.key === params.resource)
    return meta ? HttpResponse.json(meta) : notFound()
  }),

  // Names only, for ids the user can read: the palette's recents never fetch whole records.
  http.get('/api/admin/:resource/_labels', async ({ params, request }) => {
    await delay(100)
    const resource = String(params.resource)
    if (!resourceMetas.some((r) => r.key === resource)) return notFound()
    const nameOf = (id: string) => {
      const author = resource === 'authors' ? authorRows.find((r) => r.id === id) : undefined
      if (author) return authorShow(author).display_name
      const priorAuth = resource === 'content_approvals' ? approvals.find((pa) => pa.id === id) : undefined
      if (priorAuth) return approvalShow(priorAuth).display_name
      const post = resource === 'posts' ? posts.find((e) => String(e.id) === id) : undefined
      return post && postName(post)
    }
    const ids = (new URL(request.url).searchParams.get('ids') ?? '').split(',').slice(0, 20)
    return HttpResponse.json({ labels: ids.flatMap((id) => (nameOf(id) ? [{ resource, id, display_name: nameOf(id) }] : [])) })
  }),

  // The index of any resource as a download: rows and filters match the JSON list, as the gem streams them.
  http.get(/\/api\/admin\/[^/]+\.csv$/, ({ request }) => {
    const resource = new URL(request.url).pathname.split('/').at(-1)!.replace(/\.csv$/, '')
    const body = csv([['id', 'author', 'published_on'], ...posts.slice(0, 20).map((e) => [String(e.id), e.author, e.published_on])])
    return new HttpResponse(body, { headers: { 'Content-Type': 'text/csv', 'Content-Disposition': `attachment; filename="${resource}.csv"` } })
  }),

  http.get('/api/admin/:resource', async ({ params, request }) => {
    await delay(300)
    const url = new URL(request.url)
    const sp = url.searchParams
    const meta = resourceMetas.find((r) => r.key === params.resource)
    if (!meta) return notFound()

    const fixed = (cols: IndexResponse['columns'], rows: IndexResponse['rows']): IndexResponse => ({
      resource: meta.key,
      columns: cols,
      rows,
      meta: { page: 1, per_page: meta.default_per_page, total_count: rows.length, total_pages: 1, scopes: [] },
    })
    if (meta.key === 'desks') return HttpResponse.json(fixed(deskColumns, deskRows))
    if (meta.key === 'authors') return HttpResponse.json(fixed(authorColumns, authorRows))
    if (meta.key === 'content_approvals') return HttpResponse.json(fixed(approvalColumns, approvalRows))

    if (meta.key === 'attachments') {
      const page = Math.max(Number(sp.get('page')) || 1, 1)
      const perPage = Number(sp.get('per_page')) || meta.default_per_page
      const body: IndexResponse = {
        resource: meta.key,
        columns: attachmentColumns,
        rows: attachmentRows(page, perPage),
        meta: { page, per_page: perPage, total_count: null, total_pages: null, has_next_page: page < 3, scopes: [] },
      }
      return HttpResponse.json(body)
    }

    const q = [...sp].flatMap(([key, value]) => (/^q\[.+\]$/.test(key) && value ? [[key.slice(2, -1), value] as [string, string]] : []))
    const filtered = params.resource === 'posts' ? posts.filter((e) => matchesQuery(e, q)) : []
    const scopes: Scope[] = scopeDefs.slice(0, meta.scopes.length).map(({ id, name, match }) => ({
      id,
      name,
      count: filtered.filter(match).length,
    }))
    const scope = sp.get('scope') ?? meta.default_scope ?? undefined
    const order = sp.get('order') ?? meta.default_order
    const scoped = sortRows(filtered.filter(scopeDefs.find((s) => s.id === scope)?.match ?? (() => true)), order)

    const perPage = Number(sp.get('per_page')) || meta.default_per_page
    const totalPages = Math.max(1, Math.ceil(scoped.length / perPage))
    const page = Math.min(Math.max(Number(sp.get('page')) || 1, 1), totalPages)

    const body: IndexResponse = {
      resource: meta.key,
      columns: meta.key === 'posts' ? columns : columns.slice(0, 1),
      rows: scoped.slice((page - 1) * perPage, page * perPage).map((e) => ({
        id: String(e.id),
        display_name: postName(e),
        permissions: rowPermissions(e),
        actions: rowPermissions(e).show ? postRowActions(e) : [],
        cells: cellsFor(e),
      })),
      meta: { page, per_page: perPage, total_count: scoped.length, total_pages: totalPages, scopes, current_scope: scope, order },
    }
    return HttpResponse.json(body)
  }),

  http.get('/api/admin/:resource/:id', async ({ params }) => {
    await delay(200)
    const { resource, id } = params as Record<string, string>
    const meta = resourceMetas.find((r) => r.key === resource)
    if (!meta) return notFound()

    const author = resource === 'authors' ? authorRows.find((r) => r.id === id) : undefined
    if (author) return HttpResponse.json(authorShow(author))

    const priorAuth = resource === 'content_approvals' ? approvals.find((pa) => pa.id === id) : undefined
    if (priorAuth) return HttpResponse.json(approvalShow(priorAuth))

    const post = posts.find((e) => String(e.id) === id)
    if (resource === 'posts' && !post) return notFound()
    const body: ShowResponse = post
      ? {
          resource,
          id,
          title: `Post #${id}`,
          display_name: postName(post),
          permissions: rowPermissions(post),
          actions: rowPermissions(post).show ? postActions(post) : [],
          layout: showLayout(post),
        }
      : {
          resource,
          id,
          title: `${meta.label} #${id}`,
          permissions: { show: true },
          actions: [],
          layout: [{ type: 'attributes_table', rows: [{ label: 'ID', value: [{ type: 'text', text: id }] }] }],
        }
    return HttpResponse.json(body)
  }),
]
