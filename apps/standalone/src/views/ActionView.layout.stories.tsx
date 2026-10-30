import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, fn, screen, userEvent, waitFor, within } from 'storybook/test'
import type { Action, FormField, FormResponse, Node as NodeData, PageResponse } from '@/api/generated/model'
import { ActionViewBody } from './ActionView'

// A template with more than one form: a search whose results hold row actions and a form per row. The search
// answers 200 with the page again, and the layout carries the results.
const base = '/api/admin/categories/ps-1'
const lookup = `${base}/new_search_archive`

const field = (f: Partial<FormField> & Pick<FormField, 'name' | 'label' | 'control'>): FormField => ({ required: false, value: null, param: `q[${f.name}]`, ...f })

const search = (values: Record<string, string> = {}): FormResponse => ({
  resource: 'categories',
  id: 'ps-1',
  title: 'Archive lookup',
  actions: [],
  permissions: {},
  submittable: true,
  submit_label: 'Search Acme Archive Records',
  action: { method: 'post', path: `${base}/search_archive` },
  form: {
    sections: [
      {
        kind: 'inputs',
        fields: [
          field({ name: 'author_id', label: 'Author ID', control: 'text', value: values.author_id ?? null }),
          field({ name: 'first_name', label: 'First name', control: 'text', value: values.first_name ?? null }),
          field({ name: 'last_name', label: 'Last name', control: 'text', value: values.last_name ?? null }),
          field({ name: 'joined_on', label: 'Joined', control: 'date' }),
        ],
      },
    ],
  },
})

const linkRecord = (id: string): FormResponse => ({
  resource: 'categories',
  id: 'ps-1',
  title: '',
  actions: [],
  permissions: {},
  submittable: true,
  submit_label: 'Link Author',
  action: { method: 'post', path: `${base}/link_archive_record` },
  form: {
    sections: [
      {
        kind: 'inputs',
        fields: [
          field({ name: 'record_id', param: 'record_id', label: 'Record', control: 'hidden', value: id }),
          field({ name: 'author_id', param: 'author_id', label: '', control: 'text', placeholder: 'Author UUID' }),
        ],
      },
    ],
  },
})

const rematch = (id: string): Action => ({
  key: 'rematch_archive',
  label: 'Rematch',
  kind: 'member',
  placement: 'inline',
  method: 'post',
  href: `/admin/categories/ps-1/rematch_archive?record_id=${id}`,
  api_path: `${base}/rematch_archive?record_id=${id}`,
  confirm: 'Match this record to an author again?',
  enabled: true,
})

const text = (value: string): NodeData => ({ type: 'text', text: value })

const row = (id: string, first: string, last: string): NodeData[] => [
  text('—'),
  text(first),
  text(last),
  { type: 'date', value: '2024-03-09' },
  text('tech'),
  { type: 'group', children: [{ type: 'action', action: rematch(id) }, { type: 'form', form: linkRecord(id) }] },
]

const results = (): FormResponse => ({
  ...search({ first_name: 'Ada' }),
  layout: [
    { type: 'form' },
    { type: 'heading', level: 3, children: [text('2 matches')] },
    {
      type: 'table',
      headers: ['Author ID', 'First name', 'Last name', 'Joined', 'Beat', 'Actions'],
      rows: [row('rec-1', 'Ada', 'Lovelace'), row('rec-2', 'Ada', 'Byron')],
    },
  ],
})

const nothing = (): FormResponse => ({
  ...search({ first_name: 'Zed' }),
  layout: [{ type: 'form' }, { type: 'paragraph', children: [text('No matches found')] }],
})

const action: Action = {
  key: 'new_search_archive',
  label: 'Archive lookup',
  kind: 'member',
  placement: 'header',
  method: 'get',
  href: '/admin/categories/ps-1/new_search_archive',
  enabled: true,
  view: { mode: 'native', path: lookup, presentation: 'page' },
}

const meta = {
  title: 'Views/Template with layout',
  component: ActionViewBody,
  args: { action, resource: 'categories', id: 'ps-1', container: 'page', onResult: fn(), onClose: fn() },
  parameters: { viewportSize: { width: 1100, height: 760 } },
} satisfies Meta<typeof ActionViewBody>

export default meta
type Story = StoryObj<typeof meta>

const opens = http.get(lookup, () => HttpResponse.json(search()))
const answers = (body: FormResponse) => http.post(`${base}/search_archive`, () => HttpResponse.json(body))
const showsResults = http.get(lookup, () => HttpResponse.json(results()))

// A read-only template has no form: the path answers with its content as a PageResponse.
const history = (): PageResponse => ({
  key: 'categories',
  title: 'Team history',
  actions: [],
  layout: [
    {
      type: 'table',
      headers: ['Changed', 'Member', 'Role'],
      rows: [
        [{ type: 'date', value: '2026-10-02' }, text('Ada Lovelace'), text('Photographer')],
        [{ type: 'date', value: '2026-09-14' }, text('Grace Hopper'), text('Editor')],
      ],
    },
    { type: 'link', label: 'Sidekiq Dashboard', href: 'http://localhost:3003/sidekiq', external: true },
  ],
})

export const ReadOnlyTemplate: Story = {
  args: { action: { ...action, view: { mode: 'native', path: lookup, presentation: 'page' } } },
  parameters: { msw: { handlers: [http.get(lookup, () => HttpResponse.json(history()))] } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByText('Grace Hopper')).toBeVisible()
    const link = canvas.getByRole('link', { name: /Sidekiq Dashboard/ })
    await expect(link).toHaveAttribute('target', '_blank')
    await expect(link).toHaveAttribute('rel', 'noopener noreferrer')
    await expect(canvas.queryByRole('button')).toBeNull()
  },
}

export const SearchForm: Story = {
  parameters: { msw: { handlers: [opens] } },
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByRole('button', { name: 'Search Acme Archive Records' })).toBeVisible()
  },
}

export const Results: Story = {
  parameters: { msw: { handlers: [showsResults] } },
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findAllByRole('button', { name: 'Rematch' })).toHaveLength(2)
  },
}

export const ResultsDark: Story = { ...Results, globals: { theme: 'dark' } }

export const ResultsMobile: Story = { ...Results, parameters: { ...Results.parameters, viewportSize: { width: 390, height: 900 } } }

export const SearchShowsResultsInPlace: Story = {
  parameters: { msw: { handlers: [opens, answers(results())] } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.type(await canvas.findByLabelText('First name'), 'Ada')
    await userEvent.click(canvas.getByRole('button', { name: 'Search Acme Archive Records' }))
    await expect(await canvas.findByText('2 matches')).toBeVisible()
    // The form is still there, with what was typed, above the results.
    await expect(canvas.getByLabelText('First name')).toHaveValue('Ada')
    await expect(canvas.getAllByRole('button', { name: 'Link Author' })).toHaveLength(2)
  },
}

export const SearchWithNoMatches: Story = {
  parameters: { msw: { handlers: [opens, answers(nothing())] } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.type(await canvas.findByLabelText('First name'), 'Zed')
    await userEvent.click(canvas.getByRole('button', { name: 'Search Acme Archive Records' }))
    await expect(await canvas.findByText('No matches found')).toBeVisible()
  },
}

export const SearchRejected: Story = {
  parameters: {
    msw: {
      handlers: [
        opens,
        http.post(`${base}/search_archive`, () =>
          HttpResponse.json({ code: 'invalid', message: 'Review failed', errors: {}, base: ['Please provide at least 2 search terms or a Author ID'] }, { status: 422 }),
        ),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click(await canvas.findByRole('button', { name: 'Search Acme Archive Records' }))
    await expect(await canvas.findByText('Please provide at least 2 search terms or a Author ID')).toBeVisible()
  },
}

export const RowActionAsksFirst: Story = {
  parameters: { msw: { handlers: [showsResults, http.post(`${base}/rematch_archive`, () => HttpResponse.json({ ok: true, message: 'Rematch enqueued for archive record rec-1' }))] } },
  play: async ({ canvasElement }) => {
    await userEvent.click((await within(canvasElement).findAllByRole('button', { name: 'Rematch' }))[0])
    await expect(await screen.findByText('Match this record to an author again?')).toBeVisible()
    await userEvent.click(within(await screen.findByRole('alertdialog')).getByRole('button', { name: 'Rematch' }))
    await expect(await screen.findByText('Rematch enqueued for archive record rec-1')).toBeVisible()
  },
}

export const RowFormRejected: Story = {
  parameters: {
    msw: {
      handlers: [
        showsResults,
        http.post(`${base}/link_archive_record`, () =>
          HttpResponse.json({ code: 'invalid', message: 'Author not found: abc', errors: {}, base: ['Author not found: abc'] }, { status: 422 }),
        ),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.type((await canvas.findAllByPlaceholderText('Author UUID'))[0], 'abc')
    await userEvent.click(canvas.getAllByRole('button', { name: 'Link Author' })[0])
    await expect(await canvas.findByText('Author not found: abc')).toBeVisible()
  },
}

export const RowFormLinks: Story = {
  parameters: { msw: { handlers: [showsResults, http.post(`${base}/link_archive_record`, () => HttpResponse.json({ ok: true, message: 'Linked author to archive record rec-1' }))] } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.type((await canvas.findAllByPlaceholderText('Author UUID'))[0], 'pat-1')
    await userEvent.click(canvas.getAllByRole('button', { name: 'Link Author' })[0])
    await expect(await screen.findByText('Linked author to archive record rec-1')).toBeVisible()
  },
}

export const InDialogResultsGetRoom: Story = {
  args: { container: 'dialog', action: { ...action, view: { mode: 'native', path: lookup, presentation: 'dialog' } } },
  parameters: { msw: { handlers: [opens, answers(results())] } },
  play: async () => {
    const dialog = within(await screen.findByRole('dialog'))
    await userEvent.type(await dialog.findByLabelText('First name'), 'Ada')
    await userEvent.click(dialog.getByRole('button', { name: 'Search Acme Archive Records' }))
    // Results open in a new dialog that replaces the form's, so the form's element is detached by now.
    await expect(await screen.findByText('2 matches')).toBeVisible()
    await waitFor(() => expect(screen.getAllByRole('button', { name: 'Rematch' })).toHaveLength(2))
  },
}
