import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, screen, userEvent, within } from 'storybook/test'
import type { Column, Filter, IndexMeta, IndexResponse, Node, ResourceMeta, Row, Sidebar } from '@/api/generated/model'
import { cellsFor, columns, postName, posts, resourceMetas, rowPermissions } from '@/mocks/fixtures'
import { ResourceIndex } from './ResourceIndex'

const LIST = '/api/admin/posts'
const base = resourceMetas.find((r) => r.key === 'posts')!

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

const rows = (extra: (i: number) => Partial<Row> = () => ({})): Row[] =>
  posts.slice(0, 6).map((e, i) => ({
    id: String(e.id),
    display_name: postName(e),
    permissions: rowPermissions(e),
    cells: cellsFor(e),
    ...extra(i),
  }))

const respond = (list: IndexResponse, metaOverride: Partial<ResourceMeta> = {}) => ({
  msw: {
    handlers: [
      http.get(`${LIST}/_meta`, () => HttpResponse.json({ ...base, ...metaOverride })),
      http.get(LIST, () => HttpResponse.json(list)),
    ],
  },
})

const scopes = [
  { id: 'all', name: 'All', count: 120, group: 'status' },
  { id: 'embargoed', name: 'Embargoed', count: 24, group: 'status' },
  { id: 'published', name: 'Published', count: 70, group: 'status' },
  { id: 'mine', name: 'Mine', count: 12, group: 'owner' },
  { id: 'team', name: 'My team', count: 48, group: 'owner' },
]

const statusFilter: Filter = {
  name: 'publication_status',
  label: 'Status',
  control: 'checkboxes',
  multiple: true,
  param: 'publication_status_in',
  options: [
    { label: 'Pending', value: 'pending' },
    { label: 'Published', value: 'published' },
    { label: 'Rejected', value: 'rejected' },
    { label: 'Review failed', value: 'review_failed' },
  ],
}

const numbered: Column[] = [
  { key: 'n', label: '#', sortable: false, kind: 'index' },
  ...columns.slice(0, 5),
  { key: 'budget', label: 'Budget', sortable: true, align: 'right', class_name: 'danger' },
]

const info = (title: string, lines: string[]): Sidebar => ({
  title,
  layout: lines.map((text): Node => ({ type: 'text', text })),
})

const card = (e: (typeof posts)[number]): Node[] => [
  { type: 'text', text: postName(e) },
  { type: 'status', label: e.publication_status.replace('_', ' '), variant: e.publication_status === 'published' ? 'success' : 'warning' },
  { type: 'date', value: e.published_on },
]

const meta = {
  title: 'Pages/ResourceIndex/Index v3',
  component: ResourceIndex,
  parameters: { routePath: ':resource', route: '/posts', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof ResourceIndex>

export default meta
type Story = StoryObj<typeof meta>

export const ScopeGroupsAndCheckboxes: Story = {
  parameters: {
    route: '/posts?scope=embargoed&q[publication_status_in][]=pending&q[publication_status_in][]=rejected',
    ...respond(
      {
        resource: 'posts',
        columns: numbered,
        rows: rows((i) => ({
          tone: i === 1 ? 'warning' : i === 3 ? 'danger' : undefined,
          cells: { ...cellsFor(posts[i]), n: { type: 'number', value: i + 1 }, budget: { type: 'number', value: 35 + i * 5 } },
        })),
        meta: baseMeta({ scopes, current_scope: 'embargoed', title: 'Posts needing attention', default_row_actions: false, row_actions_label: 'Operations' }),
      },
      { filters: [statusFilter], scopes: [] },
    ),
  },
}

export const ScopeGroupsDark: Story = { ...ScopeGroupsAndCheckboxes, globals: { theme: 'dark' } }

export const GridViewWithSidebar: Story = {
  parameters: {
    route: '/posts?as=grid',
    ...respond(
      {
        resource: 'posts',
        columns: [],
        rows: rows((i) => ({ cells: {}, layout: card(posts[i]) })),
        meta: baseMeta({
          as: 'grid',
          view: 'grid',
          grid_columns: 3,
          sidebars: [info('About this list', ['Posts are published weekly.', 'Embargoed posts release on their embargo date.']), info('Last sync', ['Publisher, 2 hours ago'])],
        }),
      },
      {
        index_views: [
          { as: 'table', label: 'Table', default: true },
          { as: 'grid', label: 'Grid', default: false },
          { as: 'blog', label: 'Blog', default: false },
        ],
        filters: [],
      },
    ),
  },
}

export const BlogView: Story = {
  parameters: {
    route: '/posts?as=blog',
    ...respond(
      { resource: 'posts', columns: [], rows: rows((i) => ({ cells: {}, layout: card(posts[i]) })), meta: baseMeta({ as: 'blog', view: 'blog' }) },
      { index_views: [{ as: 'table', default: true }, { as: 'blog', default: false }], filters: [] },
    ),
  },
}

export const SidebarSheetOnTablet: Story = {
  parameters: {
    viewportSize: { width: 900, height: 700 },
    ...respond(
      { resource: 'posts', columns: columns.slice(0, 4), rows: rows(), meta: baseMeta({ sidebars: [info('About this list', ['Posts are published weekly.'])] }) },
      { filters: [] },
    ),
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'About this list' }))
    await expect(await screen.findByText('Posts are published weekly.')).toBeVisible()
  },
}

export const BlankSlateWithDeclaredLink: Story = {
  parameters: {
    ...respond(
      { resource: 'posts', columns, rows: [], meta: baseMeta({ total_count: 0, blank_slate: { label: 'Import posts', href: '/admin/posts/import' } }) },
      { filters: [] },
    ),
  },
}

export const BlankSlateWithoutLink: Story = {
  parameters: {
    ...respond({ resource: 'posts', columns, rows: [], meta: baseMeta({ total_count: 0, blank_slate: { label: null, href: null } }) }, { filters: [] }),
  },
}

export const NoPaginatorNoPerPage: Story = {
  parameters: {
    ...respond({ resource: 'posts', columns: columns.slice(0, 4), rows: rows(), meta: baseMeta({ paginator: false }) }, { filters: [] }),
  },
}

// A link from the classic admin carrying a filter this resource doesn't declare.
export const DroppedUndeclaredFilter: Story = {
  parameters: { route: '/posts?scope=embargoed&q[author_id_gteq]=100&q[bogus_id_eq]=7' },
}
