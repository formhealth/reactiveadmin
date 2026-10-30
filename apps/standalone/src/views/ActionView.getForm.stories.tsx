import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, fn, screen, userEvent, within } from 'storybook/test'
import type { Action } from '@/api/generated/model'
import { SIMULATOR_ACTION, simulatorHandlers } from '@/mocks/getForms'
import { ActionViewBody } from './ActionView'

// A member action whose template is a filter form (method get) with results below it. On a page the query lives in
// the address bar; in a dialog the view holds it, so closing the dialog leaves the address alone.
const action: Action = {
  key: 'preview_schedule',
  label: 'Preview schedule',
  kind: 'member',
  placement: 'header',
  method: 'get',
  href: '/admin/users/u-1/preview_schedule',
  enabled: true,
  view: { mode: 'native', path: SIMULATOR_ACTION, presentation: 'page' },
}

const meta = {
  title: 'Views/GET form',
  component: ActionViewBody,
  args: { action, resource: 'users', id: 'u-1', container: 'page', onResult: fn(), onClose: fn() },
  parameters: { msw: { handlers: simulatorHandlers }, viewportSize: { width: 1100, height: 720 } },
} satisfies Meta<typeof ActionViewBody>

export default meta
type Story = StoryObj<typeof meta>

export const Filter: Story = {
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByRole('button', { name: 'Simulate' })).toBeVisible()
  },
}

export const DeepLinkShowsResults: Story = {
  parameters: { route: '/users/u-1/actions/preview_schedule?simulation[date]=2026-10-08&simulation[channel]=newsletter' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByText('Schedule for 2026-10-08')).toBeVisible()
    await expect(canvas.getByRole('combobox', { name: /Channel/ })).toHaveTextContent('Newsletter')
  },
}

export const SubmitShowsResults: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click(await canvas.findByRole('combobox', { name: /Channel/ }))
    await userEvent.click(await screen.findByRole('option', { name: 'Newsletter' }))
    await userEvent.click(canvas.getByRole('button', { name: 'Simulate' }))
    await expect(await canvas.findByText('Newsletter: 10 slots open')).toBeVisible()
  },
}

export const InDialogKeepsItsQuery: Story = {
  args: { container: 'dialog', action: { ...action, view: { mode: 'native', path: SIMULATOR_ACTION, presentation: 'dialog' } } },
  play: async () => {
    const dialog = within(await screen.findByRole('dialog'))
    await userEvent.click(await dialog.findByRole('combobox', { name: /Channel/ }))
    await userEvent.click(await screen.findByRole('option', { name: 'Newsletter' }))
    await userEvent.click(dialog.getByRole('button', { name: 'Simulate' }))
    await expect(await dialog.findByText('Newsletter: 10 slots open')).toBeVisible()
  },
}
