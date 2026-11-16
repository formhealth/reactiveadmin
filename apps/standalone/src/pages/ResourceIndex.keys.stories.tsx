import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, screen, userEvent, waitFor, within } from 'storybook/test'
import { http, HttpResponse } from 'msw'
import { AppRoutes } from '@/AppRoutes'
import type { IndexResponse } from '@/api/generated/model'
import { postName, posts, resourceMetas, resourceSummaries, rowPermissions } from '@/mocks/fixtures'
import { manifestBody } from '@/mocks/handlers'

const meta = {
  title: 'Pages/ResourceIndex/Keys',
  component: AppRoutes,
  parameters: { layout: 'fullscreen', route: '/posts', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof AppRoutes>

export default meta
type Story = StoryObj<typeof meta>

const rowFor = (canvasElement: HTMLElement, id: string) => canvasElement.querySelector<HTMLElement>(`[data-row-id="${id}"]`)
const cursorId = (canvasElement: HTMLElement) => canvasElement.querySelector('[data-cursor]')?.getAttribute('data-row-id')

// The first story of a run also pays for the lazy page chunk and the mock worker.
const SLOW = { timeout: 10_000 }

const loaded = async (canvasElement: HTMLElement, id = '5000') => {
  await waitFor(() => expect(rowFor(canvasElement, id)).not.toBeNull(), SLOW)
  return within(canvasElement)
}

export const MovesWithJK: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('jj')
    await expect(cursorId(canvasElement)).toBe('5001')
    await expect(rowFor(canvasElement, '5001')).toHaveFocus()
    await userEvent.keyboard('k')
    await expect(cursorId(canvasElement)).toBe('5000')
    await userEvent.keyboard('kk')
    await expect(cursorId(canvasElement)).toBe('5000')
  },
}

export const MovesWithArrows: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('{ArrowDown}{ArrowDown}{ArrowDown}{ArrowUp}')
    await expect(cursorId(canvasElement)).toBe('5001')
  },
}

export const CursorIsTheOnlyRovingStop: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('j')
    const rows = [...canvasElement.querySelectorAll<HTMLElement>('[data-row-id]')]
    await expect(rows.filter((row) => row.tabIndex === 0).map((row) => row.dataset.rowId)).toEqual(['5000'])
  },
}

export const FirstRowIsATabStopBeforeAnyKey: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    const rows = [...canvasElement.querySelectorAll<HTMLElement>('[data-row-id]')]
    await expect(rows.filter((row) => row.tabIndex === 0).map((row) => row.dataset.rowId)).toEqual(['5000'])
    rowFor(canvasElement, '5000')!.focus()
    await waitFor(() => expect(cursorId(canvasElement)).toBe('5000'))
  },
}

export const CursorDark: Story = { ...MovesWithJK, globals: { theme: 'dark' } }

export const EnterOpensRow: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('j{Enter}')
    await expect(await screen.findByRole('heading', { name: 'Post #5000' })).toBeVisible()
  },
}

export const EnterOnRestrictedRowStays: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('jjjjj')
    await expect(cursorId(canvasElement)).toBe('5004')
    await userEvent.keyboard('{Enter}')
    await expect(canvasElement.querySelector('[data-row-id="5004"]')).not.toBeNull()
  },
}

export const EnterOnFocusedLinkOpensOnce: Story = {
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.click(await canvas.findByRole('checkbox', { name: 'Select record 5000' }))
    await userEvent.keyboard('{Enter}')
    await expect(canvas.queryByRole('heading', { name: 'Post #5000' })).toBeNull()
  },
}

export const XTogglesSelection: Story = {
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.keyboard('jx')
    await expect(await canvas.findByText('1 selected')).toBeVisible()
    await expect(canvas.getByRole('checkbox', { name: 'Select record 5000' })).toBeChecked()
    await userEvent.keyboard('jx')
    await expect(await canvas.findByText('2 selected')).toBeVisible()
    await userEvent.keyboard('kx')
    await expect(await canvas.findByText('1 selected')).toBeVisible()
    await expect(canvas.getByRole('checkbox', { name: 'Select record 5000' })).not.toBeChecked()
  },
}

export const XWithoutBatchActionsDoesNothing: Story = {
  parameters: { route: '/authors' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await waitFor(() => expect(canvasElement.querySelector('[data-row-id]')).not.toBeNull(), SLOW)
    await userEvent.keyboard('jx')
    await expect(canvasElement.querySelector('[data-cursor]')).not.toBeNull()
    await expect(canvas.queryAllByRole('checkbox')).toHaveLength(0)
    await expect(canvas.queryByText(/selected/)).toBeNull()
  },
}

export const SlashFocusesFilter: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('/')
    await expect(canvasElement.querySelector('#filters')).toContainElement(document.activeElement as HTMLElement)
  },
}

export const SlashWithoutFiltersDoesNothing: Story = {
  parameters: { route: '/authors' },
  play: async ({ canvasElement }) => {
    await waitFor(() => expect(canvasElement.querySelector('[data-row-id]')).not.toBeNull(), SLOW)
    await userEvent.keyboard('/')
    await expect(document.body).toHaveFocus()
  },
}

export const KeysIgnoredWhileTyping: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('/')
    const input = document.activeElement as HTMLInputElement
    await expect(input.tagName).toBe('INPUT')
    await userEvent.keyboard('jjkx?{ArrowDown}{Enter}')
    await expect(input).toHaveFocus()
    await expect(input).toHaveValue('jjkx?')
    await expect(canvasElement.querySelector('[data-cursor]')).toBeNull()
    await expect(screen.queryByRole('dialog')).toBeNull()
  },
}

export const KeysIgnoredInDialog: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('?')
    await expect(await screen.findByRole('dialog', { name: 'Keyboard shortcuts' })).toBeVisible()
    await userEvent.keyboard('jjx')
    await expect(canvasElement.querySelector('[data-cursor]')).toBeNull()
    await expect(within(canvasElement).queryByText(/selected/)).toBeNull()
  },
}

export const KeysIgnoredInCombobox: Story = {
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.click(await canvas.findByRole('combobox', { name: 'Rows per page' }))
    await expect(await screen.findByRole('listbox')).toBeVisible()
    await userEvent.keyboard('jx')
    await expect(canvasElement.querySelector('[data-cursor]')).toBeNull()
    await expect(canvas.queryByText(/selected/)).toBeNull()
  },
}

export const CursorResetsOnPageChange: Story = {
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.keyboard('jj')
    await expect(cursorId(canvasElement)).toBe('5001')
    await userEvent.click(await canvas.findByRole('button', { name: 'Next page' }))
    await waitFor(() => expect(rowFor(canvasElement, '5000')).toBeNull(), SLOW)
    await waitFor(() => expect(canvasElement.querySelector('[data-row-id]')).not.toBeNull(), SLOW)
    await expect(canvasElement.querySelector('[data-cursor]')).toBeNull()
    await userEvent.keyboard('j')
    await expect(cursorId(canvasElement)).toBe(canvasElement.querySelector('[data-row-id]')?.getAttribute('data-row-id'))
  },
}

export const CursorStaysResetWhenRevisitingPage: Story = {
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.keyboard('jj')
    await userEvent.click(await canvas.findByRole('button', { name: 'Next page' }))
    await waitFor(() => expect(rowFor(canvasElement, '5000')).toBeNull(), SLOW)
    await waitFor(() => expect(canvasElement.querySelector('[data-row-id]')).not.toBeNull(), SLOW)
    await userEvent.click(await canvas.findByRole('button', { name: 'Previous page' }))
    await waitFor(() => expect(rowFor(canvasElement, '5000')).not.toBeNull(), SLOW)
    await expect(canvasElement.querySelector('[data-cursor]')).toBeNull()
    await userEvent.keyboard('x')
    await expect(canvas.queryByText(/selected/)).toBeNull()
  },
}

export const KeysIgnoredWhileNextPageLoads: Story = {
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.click(await canvas.findByRole('button', { name: 'Next page' }))
    await userEvent.keyboard('jx')
    await expect(canvasElement.querySelector('[data-cursor]')).toBeNull()
    await waitFor(() => expect(rowFor(canvasElement, '5000')).toBeNull(), SLOW)
    await expect(canvas.queryByText(/selected/)).toBeNull()
  },
}

const sameRows = (resource: string): IndexResponse => ({
  resource,
  columns: [],
  rows: posts.slice(0, 6).map((e) => ({ id: String(e.id), display_name: postName(e), permissions: rowPermissions(e), cells: {} })),
  meta: { page: 1, per_page: 30, total_count: 6, total_pages: 1, scopes: [], current_scope: 'all', order: 'created_at_desc' },
})

const postsMeta = resourceMetas.find((r) => r.key === 'posts')!

export const CursorResetsOnResourceChange: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get('/api/admin/posts', () => HttpResponse.json(sameRows('posts'))),
        http.get('/api/admin/teams/_meta', () => HttpResponse.json({ ...postsMeta, key: 'teams', label: 'Team', plural_label: 'Teams' })),
        http.get('/api/admin/teams', () => HttpResponse.json(sameRows('teams'))),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.keyboard('jj')
    await expect(cursorId(canvasElement)).toBe('5001')
    await userEvent.click(await canvas.findByRole('treeitem', { name: /Editorial/ }))
    await userEvent.click(await canvas.findByRole('treeitem', { name: 'Teams' }))
    await expect(await canvas.findByRole('heading', { name: 'Teams' })).toBeVisible()
    await waitFor(() => expect(canvasElement.querySelector('[data-cursor]')).toBeNull())
    await userEvent.click(document.body)
    await userEvent.keyboard('xj')
    await expect(cursorId(canvasElement)).toBe('5000')
    await expect(canvas.queryByText(/selected/)).toBeNull()
  },
}

let refetchFails = false

export const KeysIgnoredWhenRefetchFailureReplacesList: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get('/api/admin/posts', () => (refetchFails ? HttpResponse.json({ error: 'boom' }, { status: 500 }) : undefined)),
        http.post('/api/admin/posts/batch_action', () => {
          refetchFails = true
          return HttpResponse.json({ ok: true, message: 'Done' })
        }),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    refetchFails = false
    const canvas = await loaded(canvasElement)
    await userEvent.keyboard('jx')
    await userEvent.click(await canvas.findByRole('button', { name: 'Lift embargo' }))
    await userEvent.click(within(await screen.findByRole('alertdialog')).getByRole('button', { name: 'Lift embargo' }))
    await expect(await canvas.findByText("Couldn't load Posts")).toBeVisible()
    await userEvent.keyboard('{Enter}?')
    const dialog = await screen.findByRole('dialog', { name: 'Keyboard shortcuts' })
    await expect(within(dialog).queryByText('Move to the next row')).toBeNull()
    await expect(canvas.getByText("Couldn't load Posts")).toBeVisible()
  },
}

export const SidebarArrowsKeepFocusInMenu: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    const items = await waitFor(() => {
      const found = [...canvasElement.querySelectorAll<HTMLElement>('[data-tree-item]')]
      expect(found.length).toBeGreaterThan(1)
      return found
    }, SLOW)
    items[0].focus()
    await userEvent.keyboard('{ArrowDown}')
    await expect(document.activeElement).toBe(items[1])
    await userEvent.keyboard('j')
    await expect(canvasElement.querySelector('[data-cursor]')).toBeNull()
    await expect(document.activeElement).toBe(items[1])
    await userEvent.keyboard('?')
    await expect(await screen.findByRole('dialog', { name: 'Keyboard shortcuts' })).toBeVisible()
  },
}

export const CardsMoveAndSelect: Story = {
  parameters: { viewportSize: { width: 390, height: 844 } },
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.keyboard('jjx')
    await expect(cursorId(canvasElement)).toBe('5001')
    await expect(canvas.getByRole('checkbox', { name: 'Select record 5001' })).toBeChecked()
  },
}

const gridList: IndexResponse = {
  resource: 'posts',
  columns: [],
  rows: posts.slice(0, 6).map((e) => ({ id: String(e.id), display_name: postName(e), permissions: rowPermissions(e), cells: {}, layout: [{ type: 'text', text: postName(e) }] })),
  meta: { page: 1, per_page: 30, total_count: 6, total_pages: 1, scopes: [], current_scope: 'all', order: 'created_at_desc', as: 'grid', view: 'grid', grid_columns: 3 },
}

const gridParameters = {
    route: '/posts?as=grid',
    msw: {
      handlers: [
        http.get('/api/admin/posts/_meta', () =>
          HttpResponse.json({ ...resourceMetas.find((r) => r.key === 'posts'), filters: [], index_views: [{ as: 'table', label: 'Table', default: true }, { as: 'grid', label: 'Grid', default: false }] }),
        ),
        http.get('/api/admin/posts', () => HttpResponse.json(gridList)),
      ],
    },
  }

export const GridViewMovesAndSelects: Story = {
  parameters: gridParameters,
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('jj')
    await expect(cursorId(canvasElement)).toBe('5001')
    await expect(rowFor(canvasElement, '5001')).toHaveFocus()
    await userEvent.keyboard('{Enter}')
    await expect(await screen.findByRole('heading', { name: 'Post #5001' })).toBeVisible()
  },
}

export const GridViewShowsSelection: Story = {
  parameters: gridParameters,
  play: async ({ canvasElement }) => {
    const canvas = await loaded(canvasElement)
    await userEvent.keyboard('jx')
    await expect(canvas.getByRole('checkbox', { name: 'Select record 5000' })).toBeChecked()
    await expect(await canvas.findByText('1 selected')).toBeVisible()
    await userEvent.click(canvas.getByRole('checkbox', { name: 'Select record 5001' }))
    await expect(await canvas.findByText('2 selected')).toBeVisible()
    await expect(canvas.getByRole('checkbox', { name: 'Select record 5001' })).toBeChecked()
  },
}

export const HelpListsIndexShortcuts: Story = {
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('?')
    const dialog = await screen.findByRole('dialog', { name: 'Keyboard shortcuts' })
    for (const label of ['Open the command palette', 'Show keyboard shortcuts', 'Focus the filters', 'Move to the next row', 'Move to the previous row', 'Open the current row', 'Select the current row'])
      await expect(within(dialog).getByText(label)).toBeVisible()
    await expect(dialog.querySelectorAll('kbd')).toHaveLength(9)
  },
}

export const HelpDark: Story = { ...HelpListsIndexShortcuts, globals: { theme: 'dark' } }

export const HelpOmitsMissingControls: Story = {
  parameters: { route: '/authors' },
  play: async ({ canvasElement }) => {
    await waitFor(() => expect(canvasElement.querySelector('[data-row-id]')).not.toBeNull(), SLOW)
    await userEvent.keyboard('?')
    const dialog = await screen.findByRole('dialog', { name: 'Keyboard shortcuts' })
    await expect(within(dialog).getByText('Move to the next row')).toBeVisible()
    await expect(within(dialog).queryByText('Select the current row')).toBeNull()
    await expect(within(dialog).queryByText('Focus the filters')).toBeNull()
  },
}

export const HelpOnHome: Story = {
  parameters: { route: '/' },
  play: async () => {
    await userEvent.keyboard('?')
    const dialog = await screen.findByRole('dialog', { name: 'Keyboard shortcuts' })
    await expect(within(dialog).getByText('Open the command palette')).toBeVisible()
    await expect(within(dialog).queryByText('Move to the next row')).toBeNull()
  },
}

const showDenied = (classic_url?: string) =>
  http.get('/api/admin/_manifest', () =>
    HttpResponse.json({ ...manifestBody, resources: resourceSummaries.map((r) => (r.key === 'posts' ? { ...r, api_denied: { actions: ['show'], classic_url } } : r)) }),
  )

export const EnterOnDeniedShowOpensClassic: Story = {
  parameters: { msw: { handlers: [showDenied('/admin/posts')] } },
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    const opened: string[] = []
    const open = window.open
    window.open = (url?: string | URL) => {
      opened.push(String(url))
      return null
    }
    try {
      await userEvent.keyboard('j{Enter}')
      await waitFor(() => expect(opened).toEqual([expect.stringMatching(/\/admin\/posts\/5000\?classic=1$/)]))
      await expect(screen.queryByRole('heading', { name: 'Post #5000' })).toBeNull()
    } finally {
      window.open = open
    }
  },
}

export const EnterOnDeniedShowWithoutClassicStays: Story = {
  parameters: { msw: { handlers: [showDenied()] } },
  play: async ({ canvasElement }) => {
    await loaded(canvasElement)
    await userEvent.keyboard('j{Enter}')
    await expect(cursorId(canvasElement)).toBe('5000')
    await expect(screen.queryByRole('heading', { name: 'Post #5000' })).toBeNull()
  },
}
