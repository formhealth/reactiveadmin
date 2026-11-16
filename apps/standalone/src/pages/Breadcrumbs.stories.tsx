import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, within } from 'storybook/test'
import { AppRoutes } from '@/AppRoutes'

const meta = {
  title: 'Pages/Breadcrumbs',
  component: AppRoutes,
  parameters: { layout: 'fullscreen', viewportSize: { width: 1440, height: 500 } },
} satisfies Meta<typeof AppRoutes>

export default meta
type Story = StoryObj<typeof meta>

const trail = async (canvasElement: HTMLElement) => within(await within(canvasElement).findByRole('navigation', { name: 'breadcrumb' }))

export const ShowLinksToTheList: Story = {
  parameters: { route: '/posts/5000' },
  play: async ({ canvasElement }) => {
    const crumbs = await trail(canvasElement)
    await expect(await crumbs.findByRole('link', { name: 'Posts' })).toHaveAttribute('href', '/posts')
    await expect(await crumbs.findByText(/Alex Nguyen/)).toHaveAttribute('aria-current', 'page')
  },
}

export const EditLinksBackToTheRecord: Story = {
  parameters: { route: '/posts/5001/edit' },
  play: async ({ canvasElement }) => {
    const crumbs = await trail(canvasElement)
    await expect(await crumbs.findByRole('link', { name: 'Posts' })).toHaveAttribute('href', '/posts')
    await expect(crumbs.getByRole('link', { name: /Jordan Johnson/ })).toHaveAttribute('href', '/posts/5001')
    await expect(crumbs.getByText('Edit')).toHaveAttribute('aria-current', 'page')
  },
}

export const NewEndsAtTheList: Story = {
  parameters: { route: '/posts/new' },
  play: async ({ canvasElement }) => {
    const crumbs = await trail(canvasElement)
    await expect(await crumbs.findByRole('link', { name: 'Posts' })).toHaveAttribute('href', '/posts')
    await expect(crumbs.getByText('New')).toHaveAttribute('aria-current', 'page')
  },
}

export const PageHasNone: Story = {
  parameters: { route: '/batch_operations' },
  play: async ({ canvasElement }) => {
    await within(canvasElement).findByRole('heading', { level: 1, name: 'Batch Operations' })
    await expect(within(canvasElement).queryByRole('navigation', { name: 'breadcrumb' })).toBeNull()
  },
}
