import { useState, type ComponentProps } from 'react'
import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, userEvent, within } from 'storybook/test'
import type { Scope } from '@/api/generated/model'
import { ScopeTabs } from './ScopeTabs'

// The order the gem sends for the dummy app's plans: groups kept together, one ungrouped scope between them.
const scopes: Scope[] = [
  { id: 'free', name: 'Free', count: 2, group: 'tier' },
  { id: 'pro', name: 'Pro', count: 1200, group: 'tier' },
  { id: 'enterprise', name: 'Enterprise', count: 1, group: 'tier' },
  { id: 'retired', name: 'Retired', count: 0 },
  { id: 'monthly', name: 'Monthly', count: 4, group: 'billing' },
  { id: 'annual', name: 'Annual', count: null, group: 'billing' },
]

const Stateful = (args: ComponentProps<typeof ScopeTabs>) => {
  const [current, setCurrent] = useState(args.current)
  return <ScopeTabs {...args} current={current} onChange={setCurrent} />
}

const meta = {
  title: 'Components/ScopeTabs',
  component: ScopeTabs,
  args: { scopes, current: 'free', onChange: () => {} },
  render: (args) => <Stateful {...args} />,
  parameters: { viewportSize: { width: 900, height: 160 } },
} satisfies Meta<typeof ScopeTabs>

export default meta
type Story = StoryObj<typeof meta>

export const MixedGroupsWithCounts: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getAllByRole('tablist').map((list) => list.getAttribute('aria-label'))).toEqual(['Tier', 'Scopes', 'Billing'])
    await expect(canvas.getByRole('tab', { name: /Free/ })).toHaveAttribute('aria-selected', 'true')
    await expect(canvas.getByRole('tab', { name: 'Pro 1,200' })).toHaveAttribute('aria-selected', 'false')
    await expect(canvas.getByRole('tab', { name: 'Annual' })).toBeVisible()

    await userEvent.click(canvas.getByRole('tab', { name: /Monthly/ }))
    await expect(canvas.getByRole('tab', { name: /Monthly/ })).toHaveAttribute('aria-selected', 'true')
    await expect(canvas.getAllByRole('tab', { selected: true })).toHaveLength(1)
  },
}

export const ActiveScopeInUngroupedRun: Story = {
  args: { current: 'retired' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getByRole('tab', { name: /Retired/ })).toHaveAttribute('aria-selected', 'true')
    await expect(canvas.getAllByRole('tab', { selected: true })).toHaveLength(1)
  },
}

export const KeyboardWithinAGroup: Story = {
  args: { current: 'monthly' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    const [tier] = canvas.getAllByRole('tablist')
    await userEvent.click(canvas.getByRole('tab', { name: /Free/ }))
    await userEvent.keyboard('{ArrowRight}')
    await expect(canvas.getByRole('tab', { name: /Pro/ })).toHaveFocus()
    await expect(canvas.getByRole('tab', { name: /Pro/ })).toHaveAttribute('aria-selected', 'true')
    await userEvent.keyboard('{End}')
    await expect(canvas.getByRole('tab', { name: /Enterprise/ })).toHaveFocus()
    await expect(within(tier).getAllByRole('tab', { selected: true })).toHaveLength(1)
    await userEvent.tab()
    await expect(canvas.getByRole('tab', { name: /Retired/ })).toHaveFocus()
  },
}

export const OneGroupNoCounts: Story = {
  args: {
    scopes: [{ id: 'all', name: 'All' }, ...scopes.slice(0, 3).map(({ count: _count, ...scope }) => scope)],
    current: 'pro',
  },
}

export const Dark: Story = { ...MixedGroupsWithCounts, globals: { theme: 'dark' } }
