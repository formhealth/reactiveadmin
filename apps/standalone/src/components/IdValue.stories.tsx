import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, screen, userEvent, within } from 'storybook/test'
import { uuid } from '@/mocks/fixtures'
import { IdValue } from './IdValue'

const ID = uuid(3)

const meta = {
  title: 'Components/IdValue',
  component: IdValue,
  args: { value: ID },
  parameters: { layout: 'centered', viewportSize: { width: 480, height: 160 } },
} satisfies Meta<typeof IdValue>

export default meta
type Story = StoryObj<typeof meta>

export const Short: Story = {}

export const Full: Story = { args: { full: true } }

export const TooltipOpen: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.hover(await within(canvasElement).findByRole('button', { name: /Copy ID/ }))
    await expect(await screen.findByRole('tooltip')).toHaveTextContent(ID)
  },
}

export const Dark: Story = { globals: { theme: 'dark' }, args: { full: true } }
