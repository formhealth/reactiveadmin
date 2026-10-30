import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, screen, userEvent, within } from 'storybook/test'
import { AppRoutes } from '@/AppRoutes'

const meta = {
  title: 'Pages/PageView',
  component: AppRoutes,
  parameters: { layout: 'fullscreen', route: '/batch_operations', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof AppRoutes>

export default meta
type Story = StoryObj<typeof meta>

export const BatchOperations: Story = {}

export const Dark: Story = { globals: { theme: 'dark' } }

export const Mobile: Story = { parameters: { viewportSize: { width: 390, height: 1200 } } }

export const NotFound: Story = { parameters: { route: '/nope', viewportSize: { width: 1280, height: 520 } } }

export const HeaderActionToast: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Refresh history' }))
    await expect(await screen.findByText('Batch history refreshed')).toBeVisible()
  },
}

export const FrameFormValidation: Story = {
  parameters: { viewportSize: { width: 1440, height: 1000 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Start batch' }))
    await expect(await within(canvasElement).findByText("can't be blank")).toBeVisible()
  },
}

export const FrameFormRedirectsToPage: Story = {
  parameters: { viewportSize: { width: 1440, height: 1000 } },
  play: async ({ canvasElement }) => {
    await userEvent.selectOptions(await within(canvasElement).findByLabelText(/Operation/), 'lift_embargoes')
    await userEvent.click(within(canvasElement).getByRole('button', { name: 'Start batch' }))
    await expect(await screen.findByText('Batch "Lift expired embargoes" started')).toBeVisible()
  },
}
