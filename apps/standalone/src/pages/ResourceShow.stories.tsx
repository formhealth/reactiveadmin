import type { Decorator, Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, screen, userEvent, within } from 'storybook/test'
import type { Node, ShowResponse } from '@/api/generated/model'
import { uuid } from '@/mocks/fixtures'
import { ResourceShow } from './ResourceShow'

const html = (markup: string): Node => ({ type: 'html', html: markup })

const htmlHeavy: ShowResponse = {
  resource: 'posts',
  id: '5000',
  title: 'Post #5000',
  permissions: { show: true },
  actions: [],
  layout: [
    {
      type: 'panel',
      title: 'Traffic',
      children: [
        html(
          '<table><thead><tr><th>Metric</th><th>Value</th><th>Taken</th></tr></thead><tbody><tr><td>Page views</td><td>18,240</td><td>Oct 14</td></tr><tr><td>Read time</td><td>4:12</td><td>Oct 15</td></tr></tbody></table>',
        ),
        html('<p>Figures synced from <a href="/admin/sources/12">source #12</a>.</p>'),
      ],
    },
    {
      type: 'box',
      tag: 'div',
      class_name: 'columns',
      children: [
        html('<h3>Editorial plan</h3><ol><li>Weekly check-in</li><li>Daily draft review</li><li>Style review</li></ol>'),
        html('<h3>Alerts</h3><ul><li>Missed deadline on Oct 12</li><li>Traffic trend above threshold</li></ul>'),
      ],
    },
    { type: 'panel', title: 'Notes', children: [html('<p><strong>Reviewed</strong> by <em>Amelia Chen</em>.</p><p>Follow up in two weeks.</p>')] },
  ],
}

const plain = (value: string): Node => ({ type: 'text', text: value })
const attributes = (rows: [string, string][]): Node => ({ type: 'attributes_table', rows: rows.map(([label, value]) => ({ label, value: [plain(value)] })) })
const panel = (title: string, ...children: Node[]): Node => ({ type: 'panel', title, children })

// A two-column show page (`columns do column ... end; column ... end end`): long values on one side, a wide table on
// the other.
const twoColumns: ShowResponse = {
  resource: 'posts',
  id: '5002',
  title: 'Post #5002',
  permissions: { show: true },
  actions: [],
  layout: [
    {
      type: 'columns',
      children: [
        {
          type: 'column',
          children: [
            panel(
              'Post details',
              attributes([
                ['Headline', 'How a small newsroom rebuilt its publishing workflow around shared editorial calendars'],
                ['Canonical URL', 'https://example.com/2026/10/how-a-small-newsroom-rebuilt-its-publishing-workflow-around-shared-editorial-calendars'],
                ['Author', 'Amelia Chen'],
                ['Summary', 'Editors, reporters and the copy desk moved planning out of email threads into one calendar, and cut late publications by half within a quarter.'],
              ]),
            ),
            panel('Publishing', attributes([['Status', 'Published'], ['Published at', 'Oct 14, 2026 09:30'], ['Embargo lifted by', 'Marcus Johnson, managing editor']])),
          ],
        },
        {
          type: 'column',
          children: [
            panel(
              'Recent comments',
              {
                type: 'table',
                headers: ['Author', 'Posted', 'Status', 'Votes', 'Excerpt'],
                rows: [
                  [plain('Priya Raman'), plain('Oct 15'), plain('Approved'), plain('12'), plain('The calendar template is exactly what our desk needed.')],
                  [plain('Lauren Thompson'), plain('Oct 16'), plain('Pending'), plain('3'), plain('Did the copy desk keep its own queue?')],
                  [plain('Sarah Chen'), plain('Oct 17'), plain('Spam'), plain('0'), plain('Great post, visit my site for more tips')],
                ],
              },
            ),
            panel('Tags', attributes([['Primary', 'Newsroom operations'], ['Secondary', 'Editorial calendars, workflow']])),
          ],
        },
      ],
    },
  ],
}

// The app's 18rem nav rail from lg up, so the content area is as wide as it is in the app.
const withRail: Decorator = (Story) => (
  <div className="flex min-h-screen">
    <div aria-hidden className="hidden w-72 shrink-0 border-r bg-sidebar lg:block" />
    <div className="min-w-0 flex-1 px-4 py-5 sm:px-6">
      <Story />
    </div>
  </div>
)

// `column span: 2` beside a plain `column`.
const [main, side] = twoColumns.layout[0].children!
const splitColumns: ShowResponse = { ...twoColumns, layout: [{ type: 'columns', children: [{ ...main, span: 2 }, side] }] }

const twoColumnStory = (width: number, response = twoColumns): Story => ({
  decorators: [withRail],
  parameters: {
    layout: 'fullscreen',
    route: '/posts/5002',
    viewportSize: { width, height: 900 },
    msw: { handlers: [http.get('/api/admin/posts/5002', () => HttpResponse.json(response))] },
  },
})

const meta = {
  title: 'Pages/ResourceShow',
  component: ResourceShow,
  parameters: { routePath: ':resource/:id', route: '/posts/5000', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof ResourceShow>

export default meta
type Story = StoryObj<typeof meta>

export const Post: Story = {}

export const UuidRecord: Story = { parameters: { route: `/authors/${uuid(2)}` } }

export const DisabledActionTooltip: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.hover(await within(canvasElement).findByRole('button', { name: 'Lift embargo' }))
    await expect(await screen.findByRole('tooltip')).toBeVisible()
  },
}

export const ConfirmDelete: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'More actions' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Delete' }))
    await expect(await screen.findByRole('alertdialog')).toBeVisible()
  },
}

export const ReadOnlyResource: Story = { parameters: { route: '/authors/100' } }

export const Mobile: Story = { parameters: { viewportSize: { width: 390, height: 844 } } }

export const MobileActionsOpen: Story = {
  parameters: { viewportSize: { width: 390, height: 600 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'More actions' }))
    await expect(await screen.findByRole('menu')).toBeVisible()
  },
}

export const Dark: Story = { globals: { theme: 'dark' } }

export const HtmlFallbackHeavy: Story = {
  parameters: { msw: { handlers: [http.get('/api/admin/posts/5000', () => HttpResponse.json(htmlHeavy))] } },
}

// Below the row's container width (1024px less the rail) the columns stack; from there the side column keeps its third.
const columnBoxes = async (canvasElement: HTMLElement) => {
  const canvas = within(canvasElement)
  const column = async (title: string) => (await canvas.findByText(title)).closest('[data-slot=card]')!.parentElement!.getBoundingClientRect()
  return [await column('Post details'), await column('Recent comments')]
}
const stacked = async ({ canvasElement }: { canvasElement: HTMLElement }) => {
  const [first, second] = await columnBoxes(canvasElement)
  await expect(second.top).toBeGreaterThanOrEqual(first.bottom)
}
const sideBySide =
  (ratio = 1) =>
  async ({ canvasElement }: { canvasElement: HTMLElement }) => {
    const [first, second] = await columnBoxes(canvasElement)
    await expect(second.top).toBe(first.top)
    await expect(Math.abs(first.width / second.width - ratio)).toBeLessThan(0.05)
  }

// Columns sit side by side once the content area (not the viewport) fits two readable ones: at 1024 the nav rail
// leaves too little, so they stack.
export const TwoColumns1024: Story = { ...twoColumnStory(1024), play: stacked }
export const TwoColumns1280: Story = { ...twoColumnStory(1280), play: sideBySide() }
export const TwoColumns1440: Story = { ...twoColumnStory(1440), play: sideBySide() }
export const TwoColumnsMobile: Story = { ...twoColumnStory(390), play: stacked }

export const SplitColumns1024: Story = { ...twoColumnStory(1024, splitColumns), play: stacked }
export const SplitColumns1280: Story = { ...twoColumnStory(1280, splitColumns), play: sideBySide(2) }
export const SplitColumns1440: Story = { ...twoColumnStory(1440, splitColumns), play: sideBySide(2) }
export const SplitColumnsMobile: Story = { ...twoColumnStory(390, splitColumns), play: stacked }

const groups = (prefix: string, ...titles: string[]): Node => ({
  type: 'tabs',
  children: titles.map((title) => ({ type: 'tab', title, children: [plain(`${prefix}: ${title}`)] })),
})

// The sidebar's group is numbered after the main layout's, so neither resets the other.
export const TabsInLayoutAndSidebar: Story = {
  parameters: {
    route: '/posts/5003',
    viewportSize: { width: 1440, height: 520 },
    msw: {
      handlers: [
        http.get('/api/admin/posts/5003', () =>
          HttpResponse.json({
            ...twoColumns,
            id: '5003',
            title: 'Post #5003',
            layout: [groups('Main', 'Overview', 'History')],
            sidebars: [{ title: 'Moderation', layout: [groups('Sidebar', 'Overview', 'Queue')] }],
          } satisfies ShowResponse),
        ),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click(await canvas.findByRole('tab', { name: 'History' }))
    await expect(await canvas.findByText('Main: History')).toBeVisible()
    await userEvent.click(canvas.getByRole('tab', { name: 'Queue' }))
    await expect(await canvas.findByText('Sidebar: Queue')).toBeVisible()
    await expect(canvas.getByText('Main: History')).toBeVisible()
  },
}

export const NotFound: Story = { parameters: { route: '/posts/999999' } }

const author = `/authors/${uuid(0)}`

export const TabsAndColumns: Story = { parameters: { route: author } }

export const TabsAndColumnsDark: Story = { globals: { theme: 'dark' }, parameters: { route: author } }

export const TabsStackOnMobile: Story = { parameters: { route: author, viewportSize: { width: 390, height: 1100 } } }

export const SelectedTabFromUrl: Story = { parameters: { route: `${author}?tab=activity`, viewportSize: { width: 1440, height: 520 } } }

export const TabClickUpdatesUrl: Story = {
  parameters: { route: author, viewportSize: { width: 1440, height: 520 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('tab', { name: 'Activity' }))
    await expect(await within(canvasElement).findByText('Draft saved: 1,240 words')).toBeVisible()
  },
}

export const FrameNodeTab: Story = { parameters: { route: `${author}?tab=team`, viewportSize: { width: 1440, height: 640 } } }

export const HeaderActionsWithLinks: Story = { parameters: { route: author, viewportSize: { width: 1440, height: 260 } } }

export const HeaderActionsMobile: Story = {
  parameters: { route: author, viewportSize: { width: 390, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'More actions' }))
    await expect(await screen.findByRole('menuitem', { name: 'Team history' })).toBeVisible()
  },
}

// The welcome action shows in the header and again in the toolbar; either opens the same confirmation.
const resendWelcome = async (canvasElement: HTMLElement) => (await within(canvasElement).findAllByRole('button', { name: 'Resend welcome email' }))[0]

export const InlineActionConfirm: Story = {
  parameters: { route: author, viewportSize: { width: 1440, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await resendWelcome(canvasElement))
    await expect(await screen.findByRole('alertdialog', { name: 'Resend welcome email' })).toBeVisible()
  },
}

export const InlineActionToast: Story = {
  parameters: { route: author, viewportSize: { width: 1440, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await resendWelcome(canvasElement))
    await userEvent.click(await within(await screen.findByRole('alertdialog')).findByRole('button', { name: 'Resend welcome email' }))
    await expect(await screen.findByText('Welcome email sent')).toBeVisible()
  },
}

export const UnsupportedAction: Story = {
  parameters: { route: '/content_approvals/1042', viewportSize: { width: 1440, height: 420 } },
  play: async ({ canvasElement }) => {
    await userEvent.hover(await within(canvasElement).findByRole('button', { name: 'Print proof' }))
    await expect(await screen.findByRole('tooltip')).toBeVisible()
  },
}

export const DisplayNameBreadcrumb: Story = { parameters: { route: '/content_approvals/1043', viewportSize: { width: 1440, height: 420 } } }
