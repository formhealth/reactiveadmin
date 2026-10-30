import type { Meta, StoryObj } from '@storybook/react-vite'
import { delay, http, HttpResponse } from 'msw'
import { expect, screen, userEvent, within } from 'storybook/test'
import type { IndexResponse } from '@/api/generated/model'
import { apiError } from '@/mocks/handlers'
import { columns, scopeDefs } from '@/mocks/fixtures'
import { ResourceIndex } from './ResourceIndex'

const LIST = '/api/admin/posts'

const emptyList: IndexResponse = {
  resource: 'posts',
  columns,
  rows: [],
  meta: {
    page: 1,
    per_page: 30,
    total_count: 0,
    total_pages: 1,
    scopes: scopeDefs.map(({ id, name }) => ({ id, name, count: 0 })),
    current_scope: 'all',
    order: 'created_at_desc',
  },
}

const respondWith = (...handlers: ReturnType<typeof http.get>[]) => ({ msw: { handlers } })

const meta = {
  title: 'Pages/ResourceIndex',
  component: ResourceIndex,
  parameters: { routePath: ':resource', route: '/posts', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof ResourceIndex>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const Tablet: Story = { parameters: { viewportSize: { width: 900, height: 900 } } }

export const FiltersSheetOpen: Story = {
  parameters: { route: '/posts?q[publication_status_eq]=rejected', viewportSize: { width: 900, height: 700 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Filters/ }))
  },
}

export const RecordCards: Story = { parameters: { viewportSize: { width: 390, height: 844 } } }

export const RecordCardsDark: Story = { globals: { theme: 'dark' }, parameters: { viewportSize: { width: 390, height: 844 } } }

export const ReadOnlyResource: Story = { parameters: { route: '/authors' } }

export const UuidIdCards: Story = { parameters: { route: '/authors', viewportSize: { width: 390, height: 844 } } }

export const Dark: Story = { globals: { theme: 'dark' } }

export const Loading: Story = {
  parameters: {
    ...respondWith(
      http.get(LIST, async () => {
        await delay('infinite')
        return HttpResponse.json(emptyList)
      }),
    ),
  },
}

export const Empty: Story = { parameters: respondWith(http.get(LIST, () => HttpResponse.json(emptyList))) }

export const EmptyWithFilters: Story = {
  parameters: {
    route: '/posts?q[author_id_eq]=100',
    ...respondWith(http.get(LIST, () => HttpResponse.json(emptyList))),
  },
}

export const ScopedSortedFiltered: Story = {
  parameters: {
    route: '/posts?scope=embargoed&order=published_on_desc&per_page=10&q[published_on_gteq]=2026-08-01&q[published_on_lteq]=2026-10-16',
  },
}

export const Unauthorized: Story = {
  parameters: respondWith(http.get('/api/admin/*', () => apiError(401, 'unauthorized', 'Sign in required'))),
}

export const Forbidden: Story = {
  parameters: respondWith(http.get(LIST, () => apiError(403, 'forbidden', 'Not authorized'))),
}

export const ServerError: Story = {
  parameters: respondWith(http.get(LIST, () => apiError(500, 'internal_error', 'Something went wrong on the server'))),
}

export const HeaderActionsOverflow: Story = {
  parameters: { viewportSize: { width: 390, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'More actions' }))
    await expect(await screen.findByRole('menuitem', { name: 'Publish pending' })).toBeVisible()
  },
}

export const UnsupportedActionTooltip: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.hover(await within(canvasElement).findByRole('button', { name: 'Legacy import' }))
    await expect(await screen.findByRole('tooltip')).toBeVisible()
  },
}

export const HeaderActionConfirm: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Publish pending' }))
    await expect(await screen.findByRole('alertdialog', { name: 'Publish pending' })).toBeVisible()
  },
}

export const HeaderActionToast: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Sync from publisher' }))
    await expect(await screen.findByText('Publisher sync queued')).toBeVisible()
  },
}

export const RowActionsMenu: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Actions for Alex Nguyen/ }))
    await expect(await screen.findByRole('menuitem', { name: 'Retry publication' })).toBeVisible()
  },
}

export const RowActionsCardMenu: Story = {
  parameters: { viewportSize: { width: 390, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click((await within(canvasElement).findAllByRole('button', { name: /Actions for Alex Nguyen/ }))[0])
    await expect(await screen.findByRole('menuitem', { name: 'Retry publication' })).toBeVisible()
  },
}

export const RowActionRuns: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Actions for Alex Nguyen/ }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Retry publication' }))
    await expect(await screen.findByText('Retry queued for post #5000')).toBeVisible()
  },
}

// AA's pagination_total is off: no counts, just "Page N" with previous and next.
export const WithoutTotals: Story = { parameters: { route: '/attachments?page=2', viewportSize: { width: 1440, height: 760 } } }

export const WithoutTotalsLastPage: Story = { parameters: { route: '/attachments?page=3', viewportSize: { width: 1440, height: 760 } } }

export const WithoutTotalsCards: Story = { parameters: { route: '/attachments', viewportSize: { width: 390, height: 844 } } }

export const ExportCsvLink: Story = {
  parameters: { route: '/posts?scope=embargoed&q[author_id_gteq]=100' },
  play: async ({ canvasElement }) => {
    const link = await within(canvasElement).findByRole('link', { name: 'Export CSV' })
    await expect(link).toHaveAttribute('href', expect.stringContaining('/api/admin/posts.csv?'))
    await expect(link).toHaveAttribute('href', expect.stringContaining('scope=embargoed'))
  },
}

export const DisplayNameCards: Story = { parameters: { route: '/authors', viewportSize: { width: 390, height: 844 } } }

export const AuthorRowActionsMenu: Story = {
  parameters: { route: '/authors' },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Actions for Alex Nguyen/ }))
    await expect(await screen.findByRole('menuitem', { name: 'Team history' })).toBeVisible()
  },
}
