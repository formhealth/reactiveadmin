import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, screen, userEvent, within } from 'storybook/test'
import { ResourceIndex } from './ResourceIndex'

const meta = {
  title: 'Pages/ResourceIndex/Batch',
  component: ResourceIndex,
  parameters: { routePath: ':resource', route: '/posts', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof ResourceIndex>

export default meta
type Story = StoryObj<typeof meta>

const select = async (canvasElement: HTMLElement, ids: string[]) => {
  const canvas = within(canvasElement)
  for (const id of ids) await userEvent.click(await canvas.findByRole('checkbox', { name: `Select record ${id}` }))
}

export const Selectable: Story = {
  play: async ({ canvasElement }) => {
    await within(canvasElement).findByRole('checkbox', { name: 'Select all on this page' })
  },
}

export const SelectionBar: Story = {
  play: async ({ canvasElement }) => {
    await select(canvasElement, ['5000', '5001', '5002'])
    await expect(await within(canvasElement).findByText('3 selected')).toBeVisible()
  },
}

export const SelectionBarDark: Story = { ...SelectionBar, globals: { theme: 'dark' } }

export const SelectAllOnPage: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('checkbox', { name: 'Select all on this page' }))
    await expect(await within(canvasElement).findByText('30 selected')).toBeVisible()
  },
}

export const SelectionCards: Story = {
  parameters: { viewportSize: { width: 390, height: 844 } },
  play: SelectionBar.play,
}

export const BatchConfirm: Story = {
  play: async (context) => {
    await select(context.canvasElement, ['5000', '5001'])
    await userEvent.click(await within(context.canvasElement).findByRole('button', { name: 'Delete' }))
    await expect(await screen.findByRole('alertdialog')).toBeVisible()
  },
}

export const BatchWithInputs: Story = {
  play: async (context) => {
    await select(context.canvasElement, ['5000', '5001'])
    await userEvent.click(await within(context.canvasElement).findByRole('button', { name: 'Set embargo date' }))
    await expect(await screen.findByRole('dialog', { name: 'Set embargo date' })).toBeVisible()
  },
}

export const BatchToast: Story = {
  play: async (context) => {
    await select(context.canvasElement, ['5000', '5001'])
    await userEvent.click(await within(context.canvasElement).findByRole('button', { name: 'Lift embargo' }))
    await userEvent.click(await within(await screen.findByRole('alertdialog')).findByRole('button', { name: 'Lift embargo' }))
    await expect(await screen.findByText('Lifted 2 embargoes')).toBeVisible()
  },
}
