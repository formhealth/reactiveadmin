import type { Meta, StoryObj } from '@storybook/react-vite'
import { GroupOverview } from './GroupOverview'

const meta = {
  title: 'Pages/GroupOverview',
  component: GroupOverview,
  parameters: { layout: 'padded', routePath: 'groups/*', route: '/groups/setup', viewportSize: { width: 1100, height: 520 } },
} satisfies Meta<typeof GroupOverview>

export default meta
type Story = StoryObj<typeof meta>

export const TopLevelGroup: Story = {}

export const NestedGroup: Story = { parameters: { route: '/groups/setup/billing', viewportSize: { width: 1100, height: 420 } } }

export const WithCreateQuickLinks: Story = { parameters: { route: '/groups/publishing', viewportSize: { width: 1100, height: 440 } } }

export const Dark: Story = { globals: { theme: 'dark' } }

export const Narrow: Story = { parameters: { viewportSize: { width: 390, height: 640 } } }

export const Unknown: Story = { parameters: { route: '/groups/nope', viewportSize: { width: 800, height: 320 } } }
