import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, within } from 'storybook/test'
import type { MenuItem } from '@/api/generated/model'
import { menu } from '@/mocks/fixtures'
import { MenuTree } from './MenuTree'

const leaf = (id: string, label: string): MenuItem => ({ id, label, resource: id, children: [] })

const deep: MenuItem[] = [
  { id: 'dashboard', label: 'Dashboard', url: '/admin', children: [] },
  {
    id: 'billing',
    label: 'Billing',
    children: [
      leaf('posts', 'Posts'),
      {
        id: 'advertisers',
        label: 'Advertisers',
        children: [leaf('advertisers', 'All advertisers'), { id: 'contracts', label: 'Contracts', children: [leaf('contract_terms', 'Contract terms'), leaf('rate_cards', 'Rate cards')] }],
      },
    ],
  },
  { id: 'editorial', label: 'Editorial', children: [leaf('authors', 'Authors'), leaf('teams', 'Teams')] },
  { id: 'admin', label: 'Admin', children: [leaf('users', 'Users')] },
]

const meta = {
  title: 'Menu/MenuTree',
  component: MenuTree,
  args: { items: menu },
  decorators: [
    (Story) => (
      <div className="w-72 bg-sidebar py-2">
        <Story />
      </div>
    ),
  ],
  parameters: {
    layout: 'fullscreen',
    route: '/posts',
    viewportSize: { width: 288, height: 360 },
  },
} satisfies Meta<typeof MenuTree>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {}

export const DeepNesting: Story = {
  args: { items: deep },
  parameters: {
    route: '/contract_terms',
    storage: { 'ra:menu:open': ['editorial'] },
    viewportSize: { width: 288, height: 460 },
  },
}

export const ApiDenied: Story = {
  args: {
    items: [
      { id: 'dashboard', label: 'Dashboard', url: '/admin', children: [] },
      {
        id: 'admin',
        label: 'Admin',
        children: [leaf('users', 'Users'), { id: 'staff', label: 'Staff roles', kind: 'link', resource: 'staff', url: '/admin/staff', api_denied: true, children: [] }],
      },
    ],
  },
  parameters: { route: '/users', storage: { 'ra:menu:open': ['admin'] }, viewportSize: { width: 288, height: 220 } },
  play: async ({ canvasElement }) => {
    const link = await within(canvasElement).findByRole('treeitem', { name: /Staff roles/ })
    await expect(link).toHaveAttribute('href', '/admin/staff')
    await expect(link).toHaveAttribute('target', '_blank')
  },
}

export const Filtered: Story = { args: { term: 'enc' } }

export const AllExpanded: Story = {
  parameters: { route: '/attachments', storage: { 'ra:menu:open': ['billing', 'editorial', 'admin'] }, viewportSize: { width: 288, height: 460 } },
}

export const FilteredNested: Story = {
  args: { items: deep, term: 'rate' },
  parameters: { route: '/rate_cards', viewportSize: { width: 288, height: 300 } },
}

export const FilteredShowsFullPaths: Story = {
  args: { term: 'billing' },
  parameters: { route: '/billing_plans', viewportSize: { width: 288, height: 360 } },
}

export const SetupThreeLevels: Story = {
  parameters: { route: '/rate_cards', storage: { 'ra:menu:open': ['setup', 'setup/billing'] }, viewportSize: { width: 288, height: 460 } },
}

export const GroupOverviewActive: Story = {
  parameters: { route: '/groups/setup/billing', viewportSize: { width: 288, height: 460 } },
}

export const Collapsed: Story = { parameters: { route: '/', storage: { 'ra:menu:open': [] } } }

export const Dark: Story = { globals: { theme: 'dark' }, parameters: { storage: { 'ra:menu:open': ['editorial'] } } }
