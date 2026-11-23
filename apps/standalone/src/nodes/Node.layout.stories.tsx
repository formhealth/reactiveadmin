import type { Decorator, Meta, StoryObj } from '@storybook/react-vite'
import { expect, within } from 'storybook/test'
import type { Action, Node as NodeData } from '@/api/generated/model'
import { NodeContext } from './context'
import { Node } from './Node'

const withRecord: Decorator = (Story) => (
  <NodeContext value={{ resource: 'authors', id: '9e3817e8-9e38-4e39-ae39-9e3a90c49e3b' }}>
    <Story />
  </NodeContext>
)

const text = (value: string): NodeData => ({ type: 'text', text: value })
const link = (label: string, href = '/admin/authors/1/team_history'): NodeData => ({ type: 'link', label, href })
const post: Action = { key: 'resend', label: 'Resend welcome email', kind: 'member', placement: 'inline', method: 'post', href: '/admin/authors/1/resend', api_path: '/api/admin/authors/1/resend', confirm: 'Send it again?', enabled: true }
const act: NodeData = { type: 'action', action: post }

const panel = (title: string, ...children: NodeData[]): NodeData => ({ type: 'panel', title, children })
const lines = (...items: string[]): NodeData => ({ type: 'list', ordered: false, children: items.map((item) => ({ type: 'list_item', children: [text(item)] })) })

const row = (children: NodeData[], breakpoint: 'sm' | 'md' | 'lg' | 'xl' | null = 'lg'): NodeData => ({
  type: 'box',
  tag: 'div',
  layout: { display: 'flex', direction: 'row', breakpoint, gap: 4 },
  children,
})

const half = (...children: NodeData[]): NodeData => ({ type: 'box', width: '1/2', children })

const meta = {
  title: 'Nodes/Layout',
  component: Node,
  decorators: [withRecord],
  parameters: { layout: 'padded', viewportSize: { width: 1100, height: 420 } },
} satisfies Meta<typeof Node>

export default meta
type Story = StoryObj<typeof meta>

export const RowWithPanelsAndToolbars: Story = {
  args: {
    node: row([
      half(panel('Contact', { type: 'attributes_table', rows: [{ label: 'Email', value: [text('alex@example.com')] }, { label: 'Portal token', value: [{ type: 'masked' }] }] }, { type: 'toolbar', align: 'end', children: [link('Edit contact'), act] })),
      half(panel('Team', lines('Amelia Chen, lead editor', 'Marcus Johnson'), { type: 'toolbar', children: [link('Team history'), link('New member')] })),
    ]),
  },
}

export const RowStacksBelowBreakpoint: Story = {
  ...RowWithPanelsAndToolbars,
  parameters: { viewportSize: { width: 600, height: 640 } },
}

export const Thirds: Story = {
  args: {
    node: row(
      [{ type: 'box', width: '1/3', children: [panel('A', text('One third'))] }, { type: 'box', width: '2/3', children: [panel('B', text('Two thirds'))] }],
      'md',
    ),
  },
}

export const Grid: Story = {
  args: {
    node: {
      type: 'box',
      layout: { display: 'grid', breakpoint: 'md', columns: 3, base_columns: 1, gap: 3 },
      children: [
        { type: 'box', span: 2, children: [panel('Wide', text('Spans two columns'))] },
        panel('Narrow', text('One column')),
        panel('Third', text('One column')),
        { type: 'box', span: 2, children: [panel('Wide again', text('Spans two columns'))] },
      ],
    },
  },
}

export const ToolbarAlignment: Story = {
  args: {
    node: {
      type: 'box',
      children: (['start', 'center', 'end'] as const).map((align): NodeData => ({ type: 'toolbar', align, children: [link(`Aligned ${align}`), act] })),
    },
  },
}

const tinted = (value: string, tone: 'muted' | 'success' | 'danger' | 'warning'): NodeData => ({ type: 'text', text: value, tone })

export const SpacingAndToneInColumn: Story = {
  args: {
    node: {
      type: 'box',
      children: [
        { type: 'box', spacing: { bottom: 4 }, marks: ['strong'], children: [text('Margin below (bottom 4), bold content')] },
        { type: 'box', spacing: { top: 2, bottom: 2 }, children: [tinted('Muted', 'muted'), tinted('Success', 'success'), tinted('Danger', 'danger'), tinted('Warning', 'warning')] },
        { type: 'box', tone: 'muted', marks: ['em'], children: [text('Muted italic box: the tone and mark apply to its content')] },
        { type: 'box', max_width: 'sm', children: [{ type: 'text', text: 'Word limit 800 to 1,200 words stays on one line even in a narrow box', nowrap: true }] },
        { type: 'toolbar', spacing: { top: 6 }, children: [link('Toolbar with margin above'), act] },
      ],
    },
  },
  parameters: { viewportSize: { width: 700, height: 420 } },
}

export const MaxWidthAndGrow: Story = {
  args: {
    node: {
      type: 'box',
      children: [
        { type: 'box', max_width: 'md', children: [panel('Capped at md', text('A form-like container does not stretch across a wide screen.'))] },
        row([{ type: 'box', grow: true, children: [panel('Grows', text('Takes the free space of the row'))] }, { type: 'box', width: '1/3', children: [panel('One third', text('Fixed share'))] }], 'md'),
      ],
    },
  },
  parameters: { viewportSize: { width: 900, height: 420 } },
}

export const PanelFooterToolbar: Story = {
  args: { node: panel('Notes', text('Prefers mornings.'), { type: 'toolbar', children: [act, link('All notes')] }) },
  parameters: { viewportSize: { width: 700, height: 260 } },
}

export const PanelHeaderActions: Story = {
  args: { node: { ...panel('Notes', text('Prefers mornings.')), header_actions: [link('All notes'), act] } },
  parameters: { viewportSize: { width: 700, height: 220 } },
  play: async ({ canvasElement }) => {
    const header = canvasElement.querySelector<HTMLElement>('[data-slot="card-header"]')!
    await expect(within(header).getByRole('link', { name: 'All notes' })).toBeVisible()
    await expect(within(header).getByRole('button', { name: 'Resend welcome email' })).toBeVisible()
  },
}

// Long text wraps; content that can't wrap (a datetime, an external link) widens its column instead of overflowing.
export const PanelTableCells: Story = {
  args: {
    node: panel('Recent comments', {
      type: 'table',
      headers: ['Author', 'Posted', 'Source', 'Excerpt'],
      rows: [
        [
          text('Priya Raman'),
          { type: 'datetime', value: '2026-10-15T09:30:00.000Z' },
          { type: 'link', label: 'newsletter.example.com/2026/10/editorial-calendars-recap', href: 'https://newsletter.example.com/2026/10/editorial-calendars-recap', external: true },
          text('The calendar template is exactly what our desk needed, and the copy desk queue finally has one owner.'),
        ],
        [
          text('Marcus Johnson'),
          { type: 'attributes_table', rows: [{ label: 'Votes', value: [text('12')] }, { label: 'Flags', value: [text('None')] }] },
          text('https://example.com/2026/10/how-a-small-newsroom-rebuilt-its-publishing-workflow'),
          text('Short reply'),
        ],
        [
          text('Sarah Chen'),
          { type: 'box', children: [{ type: 'attributes_table', rows: [{ label: 'Votes', value: [text('3')] }] }] },
          { type: 'definition_list', rows: [{ label: 'Source', value: [text('Comment form')] }] },
          text('Thanks'),
        ],
        [
          text('Jordan Johnson'),
          {
            type: 'group',
            children: [
              { type: 'attributes_table', rows: [{ label: 'Votes', value: [text('7')] }] },
              { type: 'attributes_table', rows: [{ label: 'Flags', value: [text('1')] }] },
            ],
          },
          {
            type: 'box',
            children: [
              { type: 'attributes_table', rows: [{ label: 'Status', value: [text('Pending')] }] },
              { type: 'link', label: 'newsletter.example.com/2026/10/a-much-longer-recap-of-editorial-calendars', href: 'https://newsletter.example.com/recap', external: true },
            ],
          },
          text('Mixed'),
        ],
      ],
    }),
  },
  parameters: { viewportSize: { width: 1280, height: 300 } },
  play: async ({ canvasElement }) => {
    for (const cell of canvasElement.querySelectorAll<HTMLElement>('td')) {
      for (const child of cell.querySelectorAll<HTMLElement>('time, a')) {
        await expect(child.getBoundingClientRect().right).toBeLessThanOrEqual(cell.getBoundingClientRect().right)
      }
    }
    const canvas = within(canvasElement)
    await expect(canvas.getByText(/calendar template/).getBoundingClientRect().height).toBeGreaterThan(30)
    await expect(canvas.getByText(/^https:\/\/example\.com/).getBoundingClientRect().width).toBeLessThanOrEqual(241)
    for (const dl of canvasElement.querySelectorAll<HTMLElement>('td dl')) await expect(dl.getBoundingClientRect().width).toBeGreaterThan(100)
  },
}

// AA's `column max_width: "320px"` and `min_width:` hold whatever the share would be.
export const ColumnWidthLimits: Story = {
  args: {
    node: {
      type: 'columns',
      children: [
        { type: 'column', children: [panel('Post', text('Uneven shares'))] },
        { type: 'column', max_width_css: '320px', children: [panel('Tags', text('Capped at 320px'))] },
        { type: 'column', min_width_css: '400px', children: [panel('Comments', text('At least 400px'))] },
      ],
    },
  },
  parameters: { viewportSize: { width: 1400, height: 300 } },
  play: async ({ canvasElement }) => {
    const width = (title: string) => within(canvasElement).getByText(title).closest('[data-slot=card]')!.parentElement!.getBoundingClientRect().width
    await expect(width('Tags')).toBeLessThanOrEqual(320)
    await expect(width('Comments')).toBeGreaterThanOrEqual(400)
  },
}

const cardColumn = (canvasElement: HTMLElement, title: string) => within(canvasElement).getByText(title).closest('[data-slot=card]')!.parentElement!

// As in AA, a percentage limit is of the whole row, and a min width holds when the columns stack.
export const ColumnRelativeLimits: Story = {
  args: {
    node: {
      type: 'columns',
      children: [
        { type: 'column', min_width_css: '420px', children: [panel('Post', text('At least 420px'))] },
        { type: 'column', max_width_css: '50%', children: [panel('Tags', text('Up to half the row'))] },
      ],
    },
  },
  parameters: { viewportSize: { width: 1100, height: 300 } },
  play: async ({ canvasElement }) => {
    const row = canvasElement.querySelector<HTMLElement>('.\\@container')!.getBoundingClientRect().width
    await expect(cardColumn(canvasElement, 'Tags').getBoundingClientRect().width).toBeGreaterThan(row * 0.4)
  },
}

export const ColumnMinWidthStacked: Story = {
  ...ColumnRelativeLimits,
  parameters: { viewportSize: { width: 390, height: 400 } },
  play: async ({ canvasElement }) => {
    await expect(cardColumn(canvasElement, 'Post').getBoundingClientRect().width).toBeGreaterThanOrEqual(420)
  },
}

export const OrderedList: Story = {
  args: { node: { type: 'list', ordered: true, children: [{ type: 'list_item', children: [text('Verify sources')] }, { type: 'list_item', children: [text('Schedule intake')] }] } },
  parameters: { viewportSize: { width: 500, height: 160 } },
}

export const MaskedValue: Story = {
  args: { node: { type: 'masked' } },
  parameters: { viewportSize: { width: 300, height: 100 } },
}

// A node type from a newer server: its text, or its children, still show.
export const UnknownNodeFallsBack: Story = {
  args: { node: { type: 'sparkline' as never, label: 'Trend: steady', children: undefined } },
  parameters: { viewportSize: { width: 400, height: 100 } },
}
