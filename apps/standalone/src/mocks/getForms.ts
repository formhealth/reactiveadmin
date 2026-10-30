import { delay, http, HttpResponse } from 'msw'
import type { FormField, FormResponse, Node as NodeData, OptionsResponse, PageResponse } from '@/api/generated/model'

// A filter-and-results view as the gem serves it: a form whose method is get, and the results below it. The
// handlers read the query like the host action does, so the stories show what the client sent.
export const SIMULATOR_PAGE = '/api/admin/_pages/schedule_preview'
export const SIMULATOR_ACTION = '/api/admin/users/u-1/preview_schedule'

const channels = [
  { value: 'web', label: 'Web' },
  { value: 'newsletter', label: 'Newsletter' },
]

const editors: Record<string, { value: string; label: string; slots: number; held: number }[]> = {
  web: [
    { value: 'p-1', label: 'Ines Alvarez', slots: 6, held: 2 },
    { value: 'p-2', label: 'Tomas Berg', slots: 4, held: 0 },
  ],
  newsletter: [
    { value: 'p-3', label: 'Wen Zhao', slots: 9, held: 3 },
    { value: 'p-4', label: 'Noor Haddad', slots: 5, held: 1 },
    { value: 'p-5', label: 'Amelie Roux', slots: 2, held: 2 },
  ],
}

type Query = { date: string; channel: string; editor: string }

const queryOf = (url: URL): Query => ({
  date: url.searchParams.get('simulation[date]') ?? '',
  channel: url.searchParams.get('simulation[channel]') ?? '',
  editor: url.searchParams.get('simulation[editor]') ?? '',
})

const text = (value: string): NodeData => ({ type: 'text', text: value })

const field = (f: Partial<FormField> & Pick<FormField, 'name' | 'label' | 'control'>): FormField => ({ required: false, value: null, param: `simulation[${f.name}]`, ...f })

// The option search is the page itself with the page's query carried along, so what the options depend on is there.
const optionsPath = (base: string, q: Query, context: string) => {
  const query = new URLSearchParams()
  if (q.date) query.set('simulation[date]', q.date)
  if (q.channel) query.set('simulation[channel]', q.channel)
  query.set('context', context)
  if (context === 'page_form') query.set('form', '0')
  query.set('field', 'editor')
  return `${base}?${query}`
}

export const simulatorForm = (path: string, q: Query, context: string): FormResponse => {
  const chosen = editors[q.channel]?.find((p) => p.value === q.editor)
  return {
    resource: 'schedule_preview',
    title: '',
    actions: [],
    permissions: {},
    submittable: true,
    submit_label: 'Simulate',
    action: { method: 'get', path },
    form: {
      sections: [
        {
          kind: 'inputs',
          fields: [
            field({ name: 'date', label: 'Date', control: 'date', value: q.date || '2026-10-01', required: true }),
            field({ name: 'channel', label: 'Channel', control: 'select', value: q.channel || 'web', options: channels, required: true }),
            field({
              name: 'editor',
              label: 'Editor',
              control: 'typeahead',
              value: q.editor || null,
              options: chosen ? [{ value: chosen.value, label: chosen.label }] : [],
              options_path: optionsPath(path, q, context),
            }),
          ],
        },
      ],
    },
  }
}

const results = (q: Query): NodeData[] => {
  if (!q.date) return [text('Choose a date and a channel to see what each editor can take.')]
  const rows = (editors[q.channel || 'web'] ?? []).filter((p) => !q.editor || p.value === q.editor)
  return [
    {
      type: 'panel',
      title: `Schedule for ${q.date}`,
      children: [text(`${channels.find((v) => v.value === (q.channel || 'web'))?.label}: ${rows.reduce((sum, p) => sum + p.slots - p.held, 0)} slots open`)],
    },
    {
      type: 'table',
      headers: ['Editor', 'Slots', 'Held', 'Open'],
      rows: rows.map((p) => [text(p.label), { type: 'number', value: p.slots }, { type: 'number', value: p.held }, { type: 'number', value: p.slots - p.held }]),
    },
  ]
}

const options = (q: Query, term: string): OptionsResponse => ({
  options: (editors[q.channel || 'web'] ?? []).filter((p) => p.label.toLowerCase().includes(term.toLowerCase())).map(({ value, label }) => ({ value, label })),
  truncated: false,
})

const page = (q: Query): PageResponse => ({
  key: 'schedule_preview',
  title: 'Schedule preview',
  actions: [],
  layout: [{ type: 'form', form: simulatorForm(SIMULATOR_PAGE, q, 'page_form') }, ...results(q)],
})

const template = (q: Query): FormResponse => ({ ...simulatorForm(SIMULATOR_ACTION, q, 'template'), title: 'Preview schedule', layout: [{ type: 'form' }, ...results(q)] })

export const simulatorHandlers = [
  http.get(SIMULATOR_PAGE, async ({ request }) => {
    const url = new URL(request.url)
    await delay(120)
    return url.searchParams.get('context') === 'page_form' ? HttpResponse.json(options(queryOf(url), url.searchParams.get('term') ?? '')) : HttpResponse.json(page(queryOf(url)))
  }),
  http.get(SIMULATOR_ACTION, async ({ request }) => {
    const url = new URL(request.url)
    await delay(120)
    return url.searchParams.get('context') === 'template' ? HttpResponse.json(options(queryOf(url), url.searchParams.get('term') ?? '')) : HttpResponse.json(template(queryOf(url)))
  }),
]
