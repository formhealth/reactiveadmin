import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, userEvent, within } from 'storybook/test'
import type { Degradation, IndexResponse, Node, PageResponse, ShowResponse } from '@/api/generated/model'
import { deskColumns, deskRows } from '@/mocks/forms'
import { ResourceIndex } from './ResourceIndex'
import { ResourceShow } from './ResourceShow'
import { PageView } from './PageView'

const raw = (node: Record<string, unknown>) => node as unknown as Node

const degraded: Degradation[] = [
  { kind: 'sidebar_dropped', where: 'show/sidebar[0]', reason: 'a sidebar built from custom markup was left out' },
  { kind: 'cell_failed', where: 'show/panel[1]', reason: 'one value could not be calculated and is marked as unavailable' },
]

const show: ShowResponse = {
  resource: 'posts',
  id: '5000',
  title: 'Post #5000',
  permissions: { show: true },
  actions: [],
  degraded,
  layout: [
    {
      type: 'attributes_table',
      title: 'Post',
      rows: [
        { label: 'Author', value: [{ type: 'text', text: 'Alex Nguyen' }] },
        { label: 'Plan', value: [raw({ type: 'error', label: 'SEO plan' })] },
        { label: 'Publication status', value: [{ type: 'status', label: 'Published', variant: 'success' }] },
        { label: 'Publisher response', value: [raw({ type: 'code', language: 'json', text: '{\n  "status": "accepted",\n  "ref_id": "c-5000"\n}' })] },
      ],
    },
  ],
}

const index: IndexResponse = {
  resource: 'desks',
  columns: deskColumns,
  rows: deskRows,
  degraded,
  meta: { page: 1, per_page: 30, total_count: deskRows.length, total_pages: 1, scopes: [] },
}

const page: PageResponse = {
  key: 'batch_operations',
  title: 'Batch operations',
  actions: [],
  degraded: [degraded[0]],
  layout: [{ type: 'panel', title: 'Recent batches', children: [{ type: 'text', text: 'No batches have run yet.' }] }],
}

const meta = {
  title: 'Pages/Degraded',
  component: ResourceShow,
  parameters: { routePath: ':resource/:id', route: '/posts/5000', viewportSize: { width: 1280, height: 640 } },
} satisfies Meta<typeof ResourceShow>

export default meta
type Story = StoryObj<typeof meta>

export const ShowPage: Story = {
  parameters: { msw: { handlers: [http.get('/api/admin/posts/5000', () => HttpResponse.json(show))] } },
}

export const ShowPageExpanded: Story = {
  ...ShowPage,
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /What changed/ }))
    await expect(await within(canvasElement).findByText('A sidebar built from custom markup was left out.')).toBeVisible()
  },
}

export const ShowPageDark: Story = { ...ShowPage, globals: { theme: 'dark' } }

export const ShowPageMobile: Story = { ...ShowPage, parameters: { ...ShowPage.parameters, viewportSize: { width: 390, height: 800 } } }

export const IndexPage: StoryObj<typeof ResourceIndex> = {
  render: () => <ResourceIndex />,
  parameters: { routePath: ':resource', route: '/desks', msw: { handlers: [http.get('/api/admin/desks', () => HttpResponse.json(index))] } },
}

export const CustomPage: StoryObj<typeof PageView> = {
  render: () => <PageView />,
  parameters: { routePath: 'pages/:page', route: '/pages/batch_operations', msw: { handlers: [http.get('/api/admin/_pages/batch_operations', () => HttpResponse.json(page))] } },
}
