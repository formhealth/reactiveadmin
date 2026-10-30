import type { Meta, StoryObj } from '@storybook/react-vite'
import { delay, http, HttpResponse } from 'msw'
import { expect, screen, userEvent, within } from 'storybook/test'
import { DiscardDialog, ResourceForm } from './ResourceForm'

const meta = {
  title: 'Pages/ResourceForm',
  component: ResourceForm,
  args: { mode: 'edit' },
  parameters: { routePath: ':resource/:id/edit', route: '/posts/5001/edit', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof ResourceForm>

export default meta
type Story = StoryObj<typeof meta>

const withNew = { mode: 'new' } as const
const newParams = { routePath: ':resource/new', route: '/posts/new' }

export const Edit: Story = {}

export const EditDark: Story = { globals: { theme: 'dark' } }

export const EditMobile: Story = { parameters: { viewportSize: { width: 390, height: 844 } } }

export const EditMobileDark: Story = { globals: { theme: 'dark' }, parameters: { viewportSize: { width: 390, height: 844 } } }

export const SavedToast: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Save changes' }))
    await expect(await screen.findByText('Jordan Johnson (Oct 13, 2026) updated')).toBeVisible()
  },
}

export const Create: Story = { args: withNew, parameters: newParams }

export const Loading: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get('/api/admin/posts/5001/edit', async () => {
          await delay('infinite')
          return HttpResponse.json({})
        }),
      ],
    },
  },
}

export const ClientValidation: Story = {
  args: withNew,
  parameters: newParams,
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Create Post' }))
    await expect(await within(canvasElement).findAllByText('Required')).toHaveLength(2)
  },
}

export const InvalidJson: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click((await within(canvasElement).findAllByRole('button', { name: 'Text' }))[0])
    const details = await within(canvasElement).findByRole('textbox', { name: /^Details/ })
    await userEvent.clear(details)
    await userEvent.type(details, '{{"author_state": "MA",')
    await expect(await within(canvasElement).findByText(/Invalid JSON/)).toBeVisible()
  },
}

const serverErrors = http.patch('/api/admin/posts/5001', () =>
  HttpResponse.json(
    {
      code: 'invalid',
      message: 'Review failed',
      errors: { embargo_until: ['must be on or after the date of service'], details: ['author_state must be a two-letter code'] },
      base: ['The publisher rejected this post: category is not on file'],
    },
    { status: 422 },
  ),
)

export const ServerErrors: Story = {
  parameters: { msw: { handlers: [serverErrors] } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Save changes' }))
    await expect(await within(canvasElement).findByText('The publisher rejected this post: category is not on file')).toBeVisible()
  },
}

export const ServerErrorsDark: Story = { ...ServerErrors, globals: { theme: 'dark' } }

export const Saving: Story = {
  parameters: {
    msw: { handlers: [http.patch('/api/admin/posts/5001', () => delay('infinite'))] },
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Save changes' }))
    await expect(await within(canvasElement).findByRole('button', { name: 'Saving…' })).toBeDisabled()
  },
}

export const Forbidden: Story = {
  parameters: { msw: { handlers: [http.get('/api/admin/posts/5001/edit', () => HttpResponse.json({ code: 'forbidden', message: 'Not authorized' }, { status: 403 }))] } },
}

export const NotFound: Story = {
  parameters: { route: '/posts/9999/edit' },
}

export const DeskWithMembers: Story = {
  parameters: { route: '/desks/desk-1/edit' },
}

export const DiscardChangesPrompt: Story = {
  parameters: { route: '/desks/desk-1/edit', routePath: ':resource/:id/edit' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.type(await canvas.findByRole('textbox', { name: /^Name/ }), ' east')
    await userEvent.click(await canvas.findByRole('link', { name: 'Desks' }))
    await expect(await screen.findByRole('alertdialog', { name: 'Discard changes?' })).toBeVisible()
  },
}

export const DiscardDialogOpen: StoryObj<typeof DiscardDialog> = {
  render: () => <DiscardDialog open onKeep={() => {}} onDiscard={() => {}} />,
  parameters: { viewportSize: { width: 700, height: 400 } },
}
