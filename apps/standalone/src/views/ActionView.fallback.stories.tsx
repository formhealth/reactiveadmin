import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { useState } from 'react'
import { expect, fn, screen, userEvent, waitFor, within } from 'storybook/test'
import type { Action } from '@/api/generated/model'
import { ActionViewBody, ActionViewOverlay } from './ActionView'

const nativePath = '/api/admin/reports/r-1/actions/audit/form'
const href = '/admin/reports/r-1/audit'

const action: Action = {
  key: 'audit',
  label: 'Audit',
  kind: 'member',
  placement: 'header',
  method: 'get',
  href,
  enabled: true,
  view: { mode: 'native', path: nativePath, presentation: 'page' },
}

const unsupported = http.get(nativePath, () =>
  HttpResponse.json({ code: 'unsupported', message: 'This action renders an HTML page; use the classic admin' }, { status: 501 }),
)
const classic = (ok = true) =>
  http.get(href, () =>
    ok
      ? new HttpResponse('<h2>Classic audit</h2><p>Rendered by ActiveAdmin.</p>', { headers: { 'Content-Type': 'text/html' } })
      : HttpResponse.json({ code: 'error', message: 'boom' }, { status: 500 }),
  )

const meta = {
  title: 'Views/Native 501 fallback',
  component: ActionViewBody,
  args: { action, resource: 'reports', id: 'r-1', container: 'page', onResult: fn(), onClose: fn() },
  parameters: { viewportSize: { width: 900, height: 500 } },
} satisfies Meta<typeof ActionViewBody>

export default meta
type Story = StoryObj<typeof meta>

export const OpensInFrame: Story = {
  parameters: { msw: { handlers: [unsupported, classic()] } },
  play: async ({ canvasElement, args }) => {
    await expect(await within(canvasElement).findByText('Classic audit')).toBeVisible()
    await expect(args.onClose).not.toHaveBeenCalled()
  },
}

export const FallbackFailureShowsError: Story = {
  parameters: { msw: { handlers: [unsupported, classic(false)] } },
  play: async ({ canvasElement, args }) => {
    await expect(await within(canvasElement).findByText("Couldn't load this page")).toBeVisible()
    await expect(args.onClose).not.toHaveBeenCalled()
  },
}

export const OverlayKeepsItsChrome: Story = {
  parameters: { msw: { handlers: [unsupported, classic()] } },
  render: (args) => <ActionViewOverlay action={{ ...args.action, view: { ...args.action.view!, presentation: 'dialog' } }} ctx={{ resource: 'reports', id: 'r-1' }} onResult={args.onResult} onClose={args.onClose} />,
  play: async ({ args }) => {
    const dialog = await screen.findByRole('dialog', { name: 'Audit' })
    await expect(await within(dialog).findByText('Classic audit')).toBeVisible()
    await userEvent.keyboard('{Escape}')
    await expect(args.onClose).toHaveBeenCalled()
  },
}

const requested: string[] = []
export const CarriesTheQueryToClassic: Story = {
  parameters: {
    route: '/reports/r-1/audit?q%5Bstatus%5D=open',
    msw: {
      handlers: [
        unsupported,
        http.get(href, ({ request }) => {
          requested.push(new URL(request.url).search)
          return new HttpResponse('<h2>Classic audit</h2>', { headers: { 'Content-Type': 'text/html' } })
        }),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    requested.length = 0
    await within(canvasElement).findByText('Classic audit')
    await waitFor(() => expect(requested.some((search) => search.includes('q%5Bstatus%5D=open'))).toBe(true))
  },
}

const other: Action = { ...action, key: 'export', label: 'Export', href: '/admin/reports/r-1/export', view: { mode: 'native', path: '/api/admin/reports/r-1/actions/export/form', presentation: 'page' } }
function Switcher(props: React.ComponentProps<typeof ActionViewBody>) {
  const [current, setCurrent] = useState(props.action)
  return (
    <>
      <button type="button" onClick={() => setCurrent(other)}>
        Next action
      </button>
      <ActionViewBody {...props} action={current} />
    </>
  )
}

export const EachActionDecidesItsOwnFallback: Story = {
  parameters: {
    msw: {
      handlers: [
        unsupported,
        classic(),
        http.get('/api/admin/reports/r-1/actions/export/form', () =>
          HttpResponse.json({ key: 'reports', title: 'Export', layout: [{ type: 'text', text: 'Native export' }], actions: [], view: { mode: 'native', path: '/api/admin/_x', presentation: 'page' } }),
        ),
      ],
    },
  },
  render: (args) => <Switcher {...args} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await canvas.findByText('Classic audit')
    await userEvent.click(canvas.getByRole('button', { name: 'Next action' }))
    await expect(await canvas.findByText('Native export')).toBeVisible()
  },
}
