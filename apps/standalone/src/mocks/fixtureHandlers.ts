import { http, HttpResponse } from 'msw'
import type { FormResponse, IndexResponse, Manifest, ResourceMeta, ShowResponse } from '@/api/generated/model'

type Section = 'meta' | 'index' | 'show' | 'new' | 'edit'
type Recorded = { meta?: ResourceMeta; index?: IndexResponse; show?: ShowResponse; new?: FormResponse; edit?: FormResponse }

// Parsed JSON by file path, as `rake reactiveadmin:fixtures` writes them. In Vite:
// `import.meta.glob('./fixtures/**/*.json', { eager: true, import: 'default' })`.
export type FixtureFiles = Record<string, unknown>

// GET handlers that answer with the recorded payloads: the manifest, and per resource its meta, first
// index page (whatever the query), the new form, and the one recorded record's show page and edit form.
// Anything else (other record ids, `_options`, `_value`) falls through to the next handler.
export function fixtureHandlers(files: FixtureFiles, { base = '/api/admin' }: { base?: string } = {}) {
  const resources = new Map<string, Recorded>()
  let manifest: Manifest | undefined
  for (const [path, body] of Object.entries(files)) {
    const [, key, section] = /([^/]+)\/(meta|index|show|new|edit)\.json$/.exec(path) ?? []
    if (key) resources.set(key, { ...resources.get(key), [section as Section]: body })
    else if (/(^|\/)_manifest\.json$/.test(path)) manifest = body as Manifest
  }

  const member = (key: string, section: 'show' | 'edit') =>
    http.get(`${base}/${key}/:id${section === 'edit' ? '/edit' : ''}`, ({ params }) => {
      const body = resources.get(key)?.[section]
      return body && body.id === params.id ? HttpResponse.json(body) : undefined
    })

  return [
    ...(manifest ? [http.get(`${base}/_manifest`, () => HttpResponse.json(manifest))] : []),
    ...[...resources].flatMap(([key, { meta, index, new: form, show, edit }]) => [
      ...(meta ? [http.get(`${base}/${key}/_meta`, () => HttpResponse.json(meta))] : []),
      ...(form ? [http.get(`${base}/${key}/new`, () => HttpResponse.json(form))] : []),
      ...(edit ? [member(key, 'edit')] : []),
      ...(show ? [member(key, 'show')] : []),
      ...(index ? [http.get(`${base}/${key}`, () => HttpResponse.json(index))] : []),
    ]),
  ]
}
