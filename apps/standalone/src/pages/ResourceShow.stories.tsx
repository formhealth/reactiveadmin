import type { Meta, StoryObj } from '@storybook/react-vite'
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
