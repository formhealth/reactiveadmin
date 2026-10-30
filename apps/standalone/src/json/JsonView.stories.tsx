import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, userEvent, waitFor, within } from 'storybook/test'
import { deep, largeArray, small, withMasked } from './fixtures'
import { JsonView } from './JsonView'

const meta = {
  title: 'JSON/View',
  component: JsonView,
  parameters: { layout: 'padded', viewportSize: { width: 900, height: 520 } },
} satisfies Meta<typeof JsonView>

export default meta
type Story = StoryObj<typeof meta>

export const Small: Story = { args: { value: small } }

export const Deep: Story = { args: { value: deep } }

export const LargeArray: Story = {
  args: { value: largeArray, maxHeight: '24rem' },
  parameters: { viewportSize: { width: 900, height: 560 } },
  play: async ({ canvasElement }) => {
    const tree = within(canvasElement).getByRole('tree')
    await expect(within(tree).getByRole('button', { name: /Show 50 more/ })).toBeTruthy()
    tree.scrollTop = tree.scrollHeight
  },
}

export const LargeArrayShowMore: Story = {
  args: { value: largeArray, maxHeight: '24rem' },
  parameters: { viewportSize: { width: 900, height: 560 } },
  play: async ({ canvasElement }) => {
    const tree = within(canvasElement).getByRole('tree')
    await userEvent.click(within(tree).getByRole('button', { name: /Show 50 more/ }))
    await within(tree).findByRole('button', { name: /140 left/ })
    await waitFor(() => {
      const id = tree.getAttribute('aria-activedescendant')
      if (id) expect(tree.querySelector(`[id="${id}"][role=treeitem]`)).not.toBeNull()
    })
    tree.scrollTop = tree.scrollHeight
  },
}

export const SearchActive: Story = {
  args: { value: deep },
  play: async ({ canvasElement }) => {
    await userEvent.type(within(canvasElement).getByLabelText('Search JSON'), 'clearing')
  },
}

export const Masked: Story = { args: { value: withMasked } }

export const Dark: Story = {
  args: { value: deep },
  globals: { theme: 'dark' },
}

export const ExpandedAll: Story = {
  args: { value: deep },
  play: async ({ canvasElement }) => {
    await userEvent.click(within(canvasElement).getByRole('button', { name: 'Expand all' }))
    await expect(within(canvasElement).getByText('latency_ms')).toBeTruthy()
  },
}
