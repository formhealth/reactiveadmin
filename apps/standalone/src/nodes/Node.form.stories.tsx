import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, screen, userEvent, waitFor, within } from 'storybook/test'
import type { FormField, FormResponse, Node as NodeData, PageResponse } from '@/api/generated/model'
import { AppRoutes } from '@/AppRoutes'
import { Node } from './Node'

const field = (f: Partial<FormField> & Pick<FormField, 'name' | 'label' | 'control'>): FormField => ({ required: false, value: null, param: `bulk_message[${f.name}]`, ...f })

const announce = (extra: Partial<FormResponse> = {}): FormResponse => ({
  resource: 'bulk_messages',
  title: '',
  actions: [],
  action: { method: 'post', path: '/api/admin/bulk_messages/create' },
  permissions: {},
  submittable: true,
  submit_label: 'Send Messages',
  form: {
    sections: [
      {
        kind: 'inputs',
        fields: [
          field({
            name: 'provider_id',
            label: 'Editor',
            control: 'select',
            required: true,
            options: [
              { label: 'Sarah Chen', value: 'u-1' },
              { label: 'Rita Dawson', value: 'u-2' },
            ],
          }),
          field({
            name: 'statuses',
            param: 'bulk_message[statuses][]',
            label: 'Status',
            control: 'checkboxes',
            options: [
              { label: 'active', value: 'active' },
              { label: 'onboarding', value: 'onboarding' },
              { label: 'paused', value: 'paused' },
            ],
            multiple: true,
          }),
          field({ name: 'message', label: 'Message', control: 'textarea', required: true, hint: 'Sent to each author as a chat message.' }),
        ],
      },
    ],
  },
  ...extra,
})

const form = (response: FormResponse): NodeData => ({ type: 'form', form: response })

const meta = {
  title: 'Nodes/Form',
  component: Node,
  parameters: { route: '/bulk_messages', viewportSize: { width: 900, height: 520 } },
} satisfies Meta<typeof Node>

export default meta
type Story = StoryObj<typeof meta>

const sendsOk = http.post('/api/admin/bulk_messages/create', () =>
  HttpResponse.json({ ok: true, message: 'Message being sent to (3 authors)', location: { url: '/admin/bulk_messages' } }),
)

const fill = async (canvas: ReturnType<typeof within>) => {
  await userEvent.click(await canvas.findByRole('combobox', { name: /Editor/ }))
  await userEvent.click(await screen.findByRole('option', { name: 'Sarah Chen' }))
  await waitFor(() => expect(document.body.style.pointerEvents).not.toBe('none'))
  await userEvent.type(canvas.getByLabelText(/Message/), 'Hello from the team')
}

export const InlineInPanel: Story = {
  args: { node: { type: 'panel', title: 'Send a message', children: [{ type: 'text', text: 'Message every author on a desk in the statuses you choose.' }, form(announce())] } },
}

export const InlineInPanelDark: Story = { ...InlineInPanel, globals: { theme: 'dark' } }

export const WithTitle: Story = { args: { node: form(announce({ title: 'New announcement' })) } }

export const SubmitsAndSaysSo: Story = {
  args: InlineInPanel.args,
  parameters: { msw: { handlers: [sendsOk] } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await fill(canvas)
    await userEvent.click(canvas.getByRole('button', { name: 'Send Messages' }))
    await expect(await screen.findByText('Message being sent to (3 authors)')).toBeInTheDocument()
    // The form starts over for the next message.
    await waitFor(() => expect(canvas.getByLabelText(/Message/)).toHaveValue(''))
  },
}

export const ValidatesBeforeSending: Story = {
  args: InlineInPanel.args,
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Send Messages' }))
    await expect((await within(canvasElement).findAllByText('Required')).length).toBeGreaterThan(0)
  },
}

export const ServerRejects: Story = {
  args: InlineInPanel.args,
  parameters: {
    msw: {
      handlers: [
        http.post('/api/admin/bulk_messages/create', () =>
          HttpResponse.json({ code: 'invalid', message: 'No authors found.', errors: {}, base: ['No authors found.'] }, { status: 422 }),
        ),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await fill(canvas)
    await userEvent.click(canvas.getByRole('button', { name: 'Send Messages' }))
    await expect(await canvas.findByText('No authors found.')).toBeInTheDocument()
    await expect(canvas.getByLabelText(/Message/)).toHaveValue('Hello from the team')
  },
}

const confirming = form(announce({ submit_label: 'Disable Self Scheduling', submit_confirm: 'Are you sure you want to disable self-scheduling for the listed authors?' }))

export const ConfirmsFirst: Story = {
  args: { node: confirming },
  parameters: { msw: { handlers: [sendsOk] } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await fill(canvas)
    await userEvent.click(canvas.getByRole('button', { name: 'Disable Self Scheduling' }))
    await expect(await screen.findByRole('alertdialog', { name: 'Disable Self Scheduling' })).toBeInTheDocument()
  },
}

export const ConfirmDeclinedSendsNothing: Story = {
  args: { node: confirming },
  parameters: {
    msw: { handlers: [http.post('/api/admin/bulk_messages/create', () => HttpResponse.json({ code: 'error', message: 'Must not be called' }, { status: 500 }))] },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await fill(canvas)
    await userEvent.click(canvas.getByRole('button', { name: 'Disable Self Scheduling' }))
    await userEvent.click(await within(await screen.findByRole('alertdialog')).findByRole('button', { name: 'Cancel' }))
    await waitFor(() => expect(screen.queryByRole('alertdialog')).toBeNull())
    await expect(canvas.getByRole('button', { name: 'Disable Self Scheduling' })).toBeEnabled()
    await expect(canvas.queryByText('Must not be called')).toBeNull()
  },
}

export const ConfirmedSends: Story = {
  args: { node: confirming },
  parameters: { msw: { handlers: [sendsOk] } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await fill(canvas)
    await userEvent.click(canvas.getByRole('button', { name: 'Disable Self Scheduling' }))
    await userEvent.click(await within(await screen.findByRole('alertdialog')).findByRole('button', { name: 'Disable Self Scheduling' }))
    await expect((await screen.findAllByText('Message being sent to (3 authors)'))[0]).toBeVisible()
  },
}

export const Mobile: Story = { ...InlineInPanel, parameters: { route: '/bulk_messages', viewportSize: { width: 390, height: 640 } } }

export const RefusesAnOffSiteAction: Story = {
  args: { node: form(announce({ action: { method: 'post', path: 'https://evil.example/collect' } })) },
  play: async ({ canvasElement }) => {
    await expect(canvasElement.querySelector('form')).toBeNull()
  },
}

// A page whose content holds the form, as `bulk_messages` serves it: nothing but a panel around a form node.
const page: PageResponse = {
  key: 'bulk_messages',
  title: 'Bulk Messages',
  actions: [],
  layout: [{ type: 'panel', title: 'Send a message', children: [form(announce())] }],
  view: { mode: 'native', path: '/api/admin/_pages/bulk_messages', presentation: 'page' },
}

export const OnAPage: StoryObj<typeof AppRoutes> = {
  render: () => <AppRoutes />,
  parameters: {
    layout: 'fullscreen',
    route: '/bulk_messages',
    msw: { handlers: [http.get('/api/admin/_pages/bulk_messages', () => HttpResponse.json(page)), sendsOk] },
    viewportSize: { width: 1280, height: 720 },
  },
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByRole('button', { name: 'Send Messages' })).toBeVisible()
  },
}
