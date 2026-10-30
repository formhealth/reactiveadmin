import type { Decorator, Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, screen, userEvent, waitFor, within } from 'storybook/test'
import type { Action, Node as NodeData } from '@/api/generated/model'
import { teamHistory } from '@/mocks/classic'
import { uuid } from '@/mocks/fixtures'
import { NodeContext } from './context'
import { Node } from './Node'

const withRecord: Decorator = (Story) => (
  <NodeContext value={{ resource: 'posts', id: '5001', name: 'Jordan Johnson (Oct 13, 2026)' }}>
    <Story />
  </NodeContext>
)

const text = (value: string): NodeData => ({ type: 'text', text: value })

const retry: Action = {
  key: 'retry_publication',
  label: 'Retry publication',
  kind: 'member',
  placement: 'inline',
  method: 'post',
  href: '/admin/posts/5001/retry_publication',
  api_path: '/api/admin/posts/5001/retry_publication',
  confirm: 'Retry publishing post #5001 to the publisher?',
  enabled: true,
}

const panel = (title: string, ...children: NodeData[]): NodeData => ({ type: 'panel', title, children })

const tabs: NodeData = {
  type: 'tabs',
  children: [
    { type: 'tab', title: 'Overview', children: [panel('Post', text('Jordan Johnson, Oct 13, 2026'))] },
    { type: 'tab', title: 'SEO', children: [panel('Coverage', text('Acme Media, WEB-1'))] },
    { type: 'tab', title: 'History', children: [panel('Events', text('Created Oct 13, published Oct 14'))] },
  ],
}

const columns: NodeData = {
  type: 'columns',
  children: [
    { type: 'column', children: [panel('Left', text('First column content'), text('More on the left'))] },
    { type: 'column', children: [panel('Middle', text('Second column content'))] },
    { type: 'column', children: [panel('Right', text('Third column content'))] },
  ],
}

const meta = {
  title: 'Nodes/Interactive',
  component: Node,
  decorators: [withRecord],
  parameters: { viewportSize: { width: 900, height: 360 } },
} satisfies Meta<typeof Node>

export default meta
type Story = StoryObj<typeof meta>

export const InlineAction: Story = { args: { node: { type: 'action', action: retry } } }

export const InlineActionInTable: Story = {
  args: {
    node: {
      type: 'attributes_table',
      rows: [
        { label: 'Status', value: [{ type: 'status', label: 'Review failed', variant: 'danger' }] },
        { label: 'Publication', value: [{ type: 'action', action: retry }] },
      ],
    },
  },
}

export const InlineActionConfirm: Story = {
  args: InlineAction.args,
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Retry publication' }))
    await expect(await screen.findByRole('alertdialog', { name: 'Retry publication' })).toBeVisible()
  },
}

export const InlineActionDisabled: Story = {
  args: { node: { type: 'action', action: { ...retry, enabled: false, disabled_reason: 'Already published' } } },
}

export const InlineActionUnsupported: Story = {
  args: { node: { type: 'action', action: { ...retry, supported: false, disabled_reason: 'Runs custom JavaScript', href: '/admin/posts/5001' } } },
}

export const InlineActionExternal: Story = {
  args: { node: { type: 'action', action: { key: 'open', label: 'Open in publisher', kind: 'link', placement: 'inline', external: true, href: 'https://example.com/refs/5001', enabled: true } } },
}

const blocked = (...nodes: NodeData[]): Story => ({
  args: { node: { type: 'group', children: [text('Rejected targets render as plain text or nothing:'), ...nodes] } },
  play: async ({ canvasElement }) => {
    await expect(canvasElement.querySelector('iframe, a[href^="javascript:"], a[href*="evil.example"]')).toBeNull()
    await expect(within(canvasElement).queryByRole('button')).toBeNull()
  },
})

export const BlockedIframe = blocked({ type: 'iframe', src: 'https://evil.example/phish', title: 'Phish' }, { type: 'iframe', src: 'javascript:alert(1)' })

export const BlockedLink = blocked(
  { type: 'link', label: 'Session expired, sign in', href: 'javascript:alert(1)' },
  { type: 'link', label: 'Sign in again', href: 'https://evil.example/login' },
  { type: 'link', label: 'Data link', href: 'data:text/html,x', external: true },
)

export const BlockedAction = blocked({ type: 'action', action: { ...retry, api_path: 'https://evil.example/api', href: 'javascript:alert(1)' } })

// A POST to a route outside the admin (an OAuth start): a button that submits a real form in the top window.
const connect: Action = {
  key: 'connect_provider',
  label: 'Connect with Google',
  kind: 'link',
  placement: 'inline',
  method: 'post',
  navigate: true,
  href: '/auth/google_oauth2',
  params: { origin: '/admin/users/7' },
  enabled: true,
}

export const NavigatingPost: Story = {
  args: { node: { type: 'action', action: connect } },
  play: async ({ canvasElement }) => {
    const button = await within(canvasElement).findByRole('button', { name: 'Connect with Google' })
    await expect(button).toBeVisible()
    await expect(canvasElement.querySelector('a')).toBeNull()
  },
}

export const NavigatingPostInTable: Story = {
  args: {
    node: {
      type: 'attributes_table',
      rows: [
        { label: 'Calendar', value: [{ type: 'status', label: 'Not connected', variant: 'warning' }] },
        { label: 'Connection', value: [{ type: 'action', action: connect }] },
      ],
    },
  },
}

export const NavigatingPostConfirm: Story = {
  args: { node: { type: 'action', action: { ...connect, confirm: 'Leave the admin to connect your Google calendar?' } } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Connect with Google' }))
    await expect(await screen.findByRole('alertdialog', { name: 'Connect with Google' })).toBeVisible()
  },
}

export const BlockedNavigatingPost = blocked(
  { type: 'action', action: { ...connect, href: 'https://evil.example/auth/google_oauth2' } },
  { type: 'action', action: { ...connect, href: '/auth/../admin/users/7/destroy' } },
  { type: 'action', action: { ...connect, href: 'javascript:alert(1)' } },
)

export const Tabs: Story = { args: { node: tabs }, parameters: { route: '/posts/5001', viewportSize: { width: 900, height: 280 } } }

export const TabsSecondSelected: Story = { args: { node: tabs }, parameters: { route: '/posts/5001?tab=seo', viewportSize: { width: 900, height: 280 } } }

const sameTitleTabs: NodeData = {
  type: 'tabs',
  children: [
    { type: 'tab', title: 'Notes', children: [panel('Editorial', text('First notes'))] },
    { type: 'tab', title: 'Notes', children: [panel('Billing', text('Second notes'))] },
  ],
}

export const TabsSameTitle: Story = {
  args: { node: sameTitleTabs },
  parameters: { route: '/posts/5001', viewportSize: { width: 900, height: 200 } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click((await canvas.findAllByRole('tab', { name: 'Notes' }))[1]!)
    await expect(await canvas.findByText('Second notes')).toBeVisible()
    await expect(canvas.queryByText('First notes')).toBeNull()
  },
}

export const ToolbarRepeatedAction: Story = {
  args: {
    node: { type: 'toolbar', children: [{ type: 'action', action: { ...retry, label: 'Refresh' } }, { type: 'action', action: { ...retry, label: 'Rebuild' } }] },
  },
  parameters: { viewportSize: { width: 500, height: 80 } },
}

export const Columns: Story = { args: { node: columns }, parameters: { viewportSize: { width: 1000, height: 240 } } }

export const ColumnsStackOnMobile: Story = { args: { node: columns }, parameters: { viewportSize: { width: 390, height: 520 } } }

export const FrameHtml: Story = {
  args: { node: { type: 'frame', src: `/admin/authors/${uuid(0)}/team_history`, html: teamHistory(uuid(0)), title: 'Team history' } },
  parameters: { viewportSize: { width: 1000, height: 640 } },
}

export const FrameHtmlDark: Story = { ...FrameHtml, globals: { theme: 'dark' } }

export const FrameLoadsFromSrc: Story = {
  args: { node: { type: 'frame', src: `/admin/authors/${uuid(0)}/team_members/new`, title: 'New team member' } },
  parameters: { viewportSize: { width: 900, height: 520 } },
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByLabelText('Name')).toBeVisible()
  },
}

export const FrameFailsToLoad: Story = {
  args: { node: { type: 'frame', src: '/admin/broken/frame' } },
  parameters: {
    msw: { handlers: [http.get('/admin/broken/frame', () => HttpResponse.json({ code: 'error', message: 'Boom' }, { status: 500 }))] },
    viewportSize: { width: 900, height: 280 },
  },
  play: async ({ canvasElement }) => {
    await waitFor(() => expect(within(canvasElement).queryByText("Couldn't load this page")).toBeTruthy(), { timeout: 4000 })
  },
}

export const IframeNode: Story = {
  args: { node: { type: 'iframe', src: '/admin/preview_schedule.html?embed=1', title: 'Preview schedule' } },
  parameters: { viewportSize: { width: 900, height: 520 } },
  play: async ({ canvasElement }) => {
    const frame = await within(canvasElement).findByTitle('Preview schedule')
    await waitFor(() => expect((frame as HTMLIFrameElement).style.height).not.toBe('480px'))
  },
}
