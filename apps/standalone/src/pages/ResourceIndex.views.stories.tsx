import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, userEvent, within } from 'storybook/test'
import type { IndexMeta, Node, Row } from '@/api/generated/model'
import { cellsFor, columns, postName, posts, resourceMetas, rowPermissions } from '@/mocks/fixtures'
import { ResourceIndex } from './ResourceIndex'

const LIST = '/api/admin/posts'
const base = resourceMetas.find((r) => r.key === 'posts')!

const views = [
  { as: 'table', label: 'Table', default: true },
  { as: 'grid', label: 'Grid', default: false },
  { as: 'blog', label: 'Blog', default: false },
  { as: 'block', label: 'List', default: false },
]

const baseMeta = (page: Partial<IndexMeta> = {}): IndexMeta => ({
  page: 1,
  per_page: 30,
  total_count: 6,
  total_pages: 1,
  scopes: [],
  current_scope: 'all',
  order: 'created_at_desc',
  ...page,
})

const rows = (layout?: (i: number) => Node[]): Row[] =>
  posts.slice(0, 6).map((e, i) => ({
    id: String(e.id),
    display_name: postName(e),
    permissions: rowPermissions(e),
    cells: layout ? {} : cellsFor(e),
    ...(layout && { layout: layout(i) }),
  }))

const card = (i: number): Node[] => [{ type: 'text', text: postName(posts[i]) }]

const byView = {
  msw: {
    handlers: [
      http.get(`${LIST}/_meta`, () => HttpResponse.json({ ...base, index_views: views, filters: [] })),
      http.get(LIST, ({ request }) => {
        const as = new URL(request.url).searchParams.get('as')
        const view = ['grid', 'blog', 'block'].find((v) => v === as) as IndexMeta['view']
        return HttpResponse.json(
          view
            ? { resource: 'posts', columns: [], rows: rows(card), meta: baseMeta({ as: view, view, grid_columns: 2 }) }
            : { resource: 'posts', columns: columns.slice(0, 4), rows: rows(), meta: baseMeta() },
        )
      }),
    ],
  },
}

const meta = {
  title: 'Pages/ResourceIndex/Views',
  component: ResourceIndex,
  parameters: { routePath: ':resource', route: '/posts', viewportSize: { width: 1440, height: 900 }, ...byView },
} satisfies Meta<typeof ResourceIndex>

export default meta
type Story = StoryObj<typeof meta>

const selectsInView = (as: string): Story => ({
  parameters: { route: `/posts?as=${as}` },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    for (const id of ['5000', '5001']) await userEvent.click(await canvas.findByRole('checkbox', { name: `Select record ${id}` }))
    await expect(await canvas.findByText('2 selected')).toBeVisible()
  },
})

export const SelectionInGrid = selectsInView('grid')
export const SelectionInBlog = selectsInView('blog')
export const SelectionInBlock = selectsInView('block')

export const SwitcherFollowsUrl: Story = {
  parameters: { route: '/posts?as=blog' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByRole('tab', { name: 'Blog', selected: true })).toBeVisible()
    await userEvent.click(canvas.getByRole('tab', { name: 'Table' }))
    await expect(await canvas.findByRole('tab', { name: 'Table', selected: true })).toBeVisible()
    await expect(await canvas.findByRole('table')).toBeVisible()
  },
}

export const UnknownViewFallsBackToDefault: Story = {
  parameters: { route: '/posts?as=nope' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByRole('tab', { name: 'Table', selected: true })).toBeVisible()
    await expect(await canvas.findByRole('table')).toBeVisible()
  },
}
