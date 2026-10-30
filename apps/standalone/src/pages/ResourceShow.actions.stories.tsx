import type { Meta, StoryObj } from '@storybook/react-vite'
import { delay, http, HttpResponse } from 'msw'
import { expect, screen, userEvent, within } from 'storybook/test'
import { ResourceShow } from './ResourceShow'

const meta = {
  title: 'Pages/ResourceShow/Actions',
  component: ResourceShow,
  parameters: { routePath: ':resource/:id', route: '/posts/5001', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof ResourceShow>

export default meta
type Story = StoryObj<typeof meta>

const open = (name: string) => async ({ canvasElement }: { canvasElement: HTMLElement }) => {
  await userEvent.click(await within(canvasElement).findByRole('button', { name }))
}

export const DestroyConfirm: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'More actions' }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Delete' }))
    await expect(await screen.findByRole('alertdialog', { name: 'Delete' })).toBeVisible()
  },
}

export const DestroyConfirmDark: Story = { ...DestroyConfirm, globals: { theme: 'dark' } }

export const MemberActionToast: Story = {
  play: async (context) => {
    await open('Retry publication')(context)
    await expect(await screen.findByText('Retry queued for post #5001')).toBeVisible()
  },
}

export const MemberActionFailed: Story = {
  parameters: {
    msw: {
      handlers: [
        http.post('/api/admin/posts/5001/retry_publication', () =>
          HttpResponse.json({ code: 'invalid', message: 'Review failed', errors: {}, base: ['Already published'] }, { status: 422 }),
        ),
      ],
    },
  },
  play: async (context) => {
    await open('Retry publication')(context)
    await expect(await screen.findByText('Already published')).toBeVisible()
  },
}

export const MemberActionForm: Story = {
  play: async (context) => {
    await open('Reschedule embargo')(context)
    await expect(await screen.findByRole('dialog', { name: /Reschedule embargo/ })).toBeVisible()
  },
}

export const MemberActionFormDark: Story = { ...MemberActionForm, globals: { theme: 'dark' } }

export const MemberActionFormValidation: Story = {
  parameters: {
    msw: {
      handlers: [
        http.post('/api/admin/posts/5001/reschedule_embargo', async () => {
          await delay(50)
          return HttpResponse.json({ code: 'invalid', message: 'Review failed', errors: { embargo_until: ['must be in the future'] }, base: [] }, { status: 422 })
        }),
      ],
    },
  },
  play: async (context) => {
    await open('Reschedule embargo')(context)
    const form = within(await screen.findByRole('dialog'))
    // The date is required, so the browser would block the submit without one; pick a past day to reach the server check.
    await userEvent.click(await form.findByRole('button', { name: /Embargo until/ }))
    await userEvent.click(within(within(await screen.findByRole('grid')).getByRole('gridcell', { name: '15' })).getByRole('button'))
    await userEvent.click(form.getByRole('button', { name: 'Reschedule embargo' }))
    await expect(await screen.findByText(/must be in the future/i)).toBeVisible()
  },
}
