import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, within } from 'storybook/test'
import { session } from '@/mocks/forms'
import { UiSwitchPanel } from './UiSwitch'

const ui = (available: boolean) => ({ msw: { handlers: [http.get('/api/admin/_session', () => HttpResponse.json({ ...session, ui: { available, default: 'classic' } }))] } })

const meta = {
  title: 'Components/UiSwitch',
  component: UiSwitchPanel,
  parameters: { route: '/authors', ...ui(true), viewportSize: { width: 640, height: 240 } },
} satisfies Meta<typeof UiSwitchPanel>

export default meta
type Story = StoryObj<typeof meta>

// Switching is a full page load, so the stories only look at what is offered.
export const Panel: Story = {
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByRole('button', { name: 'Use classic admin' })).toBeEnabled()
  },
}

export const Dark: Story = { ...Panel, globals: { theme: 'dark' } }

export const Unavailable: Story = {
  parameters: ui(false),
  play: async ({ canvasElement }) => {
    await new Promise((resolve) => setTimeout(resolve, 100))
    await expect(within(canvasElement).queryByRole('button', { name: 'Use classic admin' })).toBeNull()
  },
}
