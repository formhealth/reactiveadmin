import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, userEvent, within } from 'storybook/test'
import type { Degradation } from '@/api/generated/model'
import { DegradedNotice } from './DegradedNotice'

const degraded: Degradation[] = [
  { kind: 'sidebar_dropped', where: 'show/sidebar[0]', reason: 'a sidebar built from custom markup was left out' },
  { kind: 'cell_failed', where: 'index/column[3]', reason: 'one column could not be calculated, so its cells are blank' },
  { kind: 'cell_failed', where: 'index/column[4]', reason: 'one column could not be calculated, so its cells are blank' },
]

const meta = {
  title: 'Components/DegradedNotice',
  component: DegradedNotice,
  args: { degraded, classicHref: '/admin/posts/5000' },
  parameters: { viewportSize: { width: 900, height: 200 } },
} satisfies Meta<typeof DegradedNotice>

export default meta
type Story = StoryObj<typeof meta>

export const Collapsed: Story = {}

export const Expanded: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /What changed/ }))
    await expect(await within(canvasElement).findByText('A sidebar built from custom markup was left out.')).toBeVisible()
    await expect(within(canvasElement).getAllByText('One column could not be calculated, so its cells are blank.')).toHaveLength(1)
  },
}

export const Dismissed: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Dismiss' }))
    await expect(within(canvasElement).queryByRole('status')).toBeNull()
  },
}

export const Dark: Story = { globals: { theme: 'dark' }, play: Expanded.play }

export const Mobile: Story = { parameters: { viewportSize: { width: 360, height: 260 } }, play: Expanded.play }

export const NoClassicLink: Story = { args: { classicHref: undefined } }