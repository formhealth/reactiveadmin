import type { Meta, StoryObj } from '@storybook/react-vite'
import { userEvent, within } from 'storybook/test'
import { menu } from '@/mocks/fixtures'
import { CommandPalette } from './CommandPalette'

const meta = {
  title: 'Menu/CommandPalette',
  component: CommandPalette,
  args: { items: menu, open: true, onOpenChange: () => {} },
  parameters: { layout: 'fullscreen', viewportSize: { width: 900, height: 520 } },
} satisfies Meta<typeof CommandPalette>

export default meta
type Story = StoryObj<typeof meta>

export const Open: Story = {}

export const OpenDark: Story = { globals: { theme: 'dark' } }

// Recents are stored as pointers; the palette fetches the names when it opens.
export const WithRecentRecords: Story = {
  parameters: {
    storage: {
      'ra:recent': [
        { resource: 'posts', id: '5001', at: 3 },
        { resource: 'authors', id: '9e3817e8-9e38-4e39-ae39-9e3a90c49e3b', at: 2 },
        { resource: 'content_approvals', id: '1042', at: 1 },
      ],
    },
    viewportSize: { width: 900, height: 620 },
  },
}

export const SearchShowsFullPath: Story = {
  parameters: { viewportSize: { width: 900, height: 420 } },
  play: async ({ canvasElement }) => {
    await userEvent.type(await within(canvasElement.ownerDocument.body).findByPlaceholderText('Go to a page or recent record'), 'plans')
  },
}
