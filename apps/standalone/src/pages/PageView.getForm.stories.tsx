import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, userEvent, within } from 'storybook/test'
import { AppRoutes } from '@/AppRoutes'
import { simulatorHandlers } from '@/mocks/getForms'

// A register_page whose content is a filter form (method get) with its results below. Submitting puts the form in
// the address bar's query and fetches the page with it, so a bookmark or a reload shows the same results.
const meta = {
  title: 'Pages/GET form',
  component: AppRoutes,
  parameters: {
    layout: 'fullscreen',
    route: '/schedule_preview',
    msw: { handlers: simulatorHandlers },
    viewportSize: { width: 1280, height: 760 },
  },
} satisfies Meta<typeof AppRoutes>

export default meta
type Story = StoryObj<typeof meta>

const deepLink = '/schedule_preview?simulation[date]=2026-10-08&simulation[channel]=newsletter'

export const Filter: Story = {
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByRole('button', { name: 'Simulate' })).toBeVisible()
    await expect(within(canvasElement).getByText(/Choose a date/)).toBeVisible()
  },
}

export const DeepLinkShowsResults: Story = {
  parameters: { route: deepLink },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByText('Schedule for 2026-10-08')).toBeVisible()
    await expect(canvas.getByText('Wen Zhao')).toBeVisible()
    // The fields come back prefilled from the query.
    await expect(canvas.getByRole('combobox', { name: /Channel/ })).toHaveTextContent('Newsletter')
  },
}

export const DeepLinkDark: Story = { ...DeepLinkShowsResults, globals: { theme: 'dark' } }

export const DeepLinkMobile: Story = { ...DeepLinkShowsResults, parameters: { ...DeepLinkShowsResults.parameters, viewportSize: { width: 390, height: 1100 } } }

export const SubmitShowsResults: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click(await canvas.findByRole('combobox', { name: /Channel/ }))
    await userEvent.click(await within(document.body).findByRole('option', { name: 'Newsletter' }))
    await userEvent.click(canvas.getByRole('button', { name: 'Simulate' }))
    await expect(await canvas.findByText('Schedule for 2026-10-01')).toBeVisible()
    await expect(canvas.getByText('Newsletter: 10 slots open')).toBeVisible()
  },
}

export const OptionSearchKeepsTheQuery: Story = {
  parameters: { route: deepLink },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('combobox', { name: /Editor/ }))
    const list = within(await within(document.body).findByRole('dialog', { name: 'Editor' }))
    // Only the newsletter editors: the search carried the page's channel.
    await expect(await list.findByText('Amelie Roux')).toBeVisible()
    await expect(list.queryByText('Ines Alvarez')).toBeNull()
  },
}
