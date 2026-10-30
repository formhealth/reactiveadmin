import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, screen, userEvent, waitFor, within } from 'storybook/test'
import type { Action } from '@/api/generated/model'
import { authorShow } from '@/mocks/domain'
import { uuid } from '@/mocks/fixtures'
import { authorActions, authorRows } from '@/mocks/authors'
import { AppRoutes } from '@/AppRoutes'
import { registerCustomPage } from '@/views/customPages'

// The fallback ladder, rung by rung: native (a form from the API), frame (classic HTML restyled), iframe
// (classic page with custom JS) and custom (a host component), each from the action that opens it.
const meta = {
  title: 'Pages/Fallback ladder',
  component: AppRoutes,
  parameters: { layout: 'fullscreen', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof AppRoutes>

export default meta
type Story = StoryObj<typeof meta>

const author = `/authors/${uuid(0)}`
const click = (name: string) => async ({ canvasElement }: { canvasElement: HTMLElement }) => {
  await userEvent.click(await within(canvasElement).findByRole('button', { name }))
}
const dialog = async (name: string | RegExp) => within(await screen.findByRole('dialog', { name }))

// Replaces the author's header actions, to put one action in each presentation.
const actionsOf = (...actions: Action[]) => ({
  msw: { handlers: [http.get(`/api/admin/authors/${uuid(0)}`, () => HttpResponse.json({ ...authorShow(authorRows[0]), actions }))] },
})

const [history] = authorActions(uuid(0), 'header')

export const NativeDialog: Story = {
  parameters: { route: '/content_approvals/1042', viewportSize: { width: 1440, height: 760 } },
  play: async (context) => {
    await click('Approve')(context)
    await expect(await dialog('Approve AP-1042 · Spring issue cover story')).toBeDefined()
  },
}

export const NativeDialogDark: Story = { ...NativeDialog, globals: { theme: 'dark' } }

export const NativeValidation: Story = {
  parameters: NativeDialog.parameters,
  play: async (context) => {
    await NativeDialog.play!(context)
    const form = await dialog(/Approve/)
    await userEvent.click(form.getByRole('button', { name: 'Approve' }))
    // The browser blocks the submit on the empty required field, so nothing reaches the server.
    await expect(form.getByLabelText(/Reference number/)).toBeInvalid()
  },
}

export const NativeSuccess: Story = {
  parameters: NativeDialog.parameters,
  play: async (context) => {
    await NativeDialog.play!(context)
    const form = await dialog(/Approve/)
    await userEvent.type(await form.findByLabelText(/Reference number/), 'APR-20931')
    await userEvent.click(form.getByRole('button', { name: 'Approve' }))
    await expect(await screen.findByText('Prior authorization #1042 approved')).toBeVisible()
  },
}

export const NativeFromRowMenu: Story = {
  parameters: { route: '/content_approvals', viewportSize: { width: 1440, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Actions for AP-1042/ }))
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Approve' }))
    await expect(await dialog(/Approve AP-1042/)).toBeDefined()
  },
}

export const FramePage: Story = {
  parameters: { route: `${author}/actions/team_history`, viewportSize: { width: 1440, height: 700 } },
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByText('Lauren Thompson')).toBeVisible()
  },
}

export const FramePageDark: Story = { ...FramePage, globals: { theme: 'dark' } }

export const FramePageFromHeader: Story = {
  parameters: { route: author, viewportSize: { width: 1440, height: 700 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Team history' }))
    await expect(await within(canvasElement).findByText('Lauren Thompson')).toBeVisible()
  },
}

export const FramePageMobile: Story = { parameters: { route: `${author}/actions/team_history`, viewportSize: { width: 390, height: 760 } }, play: FramePage.play }

export const FrameConfirmRemove: Story = {
  parameters: FramePage.parameters,
  play: async ({ canvasElement }) => {
    const links = await within(canvasElement).findAllByRole('link', { name: 'Remove' })
    await userEvent.click(links[0])
    await expect(await screen.findByRole('alertdialog', { name: 'Remove' })).toBeVisible()
  },
}

export const FrameLinkRunsInFrame: Story = {
  parameters: FramePage.parameters,
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('link', { name: 'Sarah Chen' }))
    await expect(await within(canvasElement).findByText('Team member')).toBeVisible()
  },
}

export const FrameDialog: Story = {
  parameters: { route: author, viewportSize: { width: 1440, height: 700 } },
  play: async ({ canvasElement }) => {
    await click('New team member')({ canvasElement })
    await expect(await (await dialog('New team member')).findByLabelText('Name')).toBeVisible()
  },
}

export const FrameValidationError: Story = {
  parameters: FrameDialog.parameters,
  play: async (context) => {
    await FrameDialog.play!(context)
    await userEvent.click((await dialog('New team member')).getByRole('button', { name: 'Add member' }))
    await expect(await screen.findAllByText("can't be blank")).toHaveLength(2)
  },
}

export const FrameValidationErrorDark: Story = { ...FrameValidationError, globals: { theme: 'dark' } }

export const FrameRedirectToast: Story = {
  parameters: FrameDialog.parameters,
  play: async (context) => {
    await FrameDialog.play!(context)
    const form = await dialog('New team member')
    await userEvent.type(await form.findByLabelText('Name'), 'Priya Raman')
    await userEvent.selectOptions(form.getByLabelText('Role'), 'copy_editor')
    await userEvent.click(form.getByRole('button', { name: 'Add member' }))
    await expect(await screen.findByText('Priya Raman was added to the team')).toBeVisible()
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
  },
}

export const FrameInSheet: Story = {
  parameters: { route: author, viewportSize: { width: 1440, height: 700 }, ...actionsOf({ ...history, view: { ...history.view!, presentation: 'sheet' } }) },
  play: async ({ canvasElement }) => {
    await click('Team history')({ canvasElement })
    await expect(await (await dialog('Team history')).findByText('Lauren Thompson')).toBeVisible()
  },
}

export const DatePickerReplacesClassicWidget: Story = {
  parameters: { route: '/batch_operations', viewportSize: { width: 1440, height: 900 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /^Run on/ }))
    await expect(await screen.findByRole('grid')).toBeVisible()
  },
}

export const IframePage: Story = {
  parameters: { route: `${author}/actions/preview_schedule`, viewportSize: { width: 1440, height: 640 } },
  play: async ({ canvasElement }) => {
    const frame = await within(canvasElement).findByTitle('Preview schedule')
    await waitFor(() => expect((frame as HTMLIFrameElement).style.height).not.toBe('480px'))
  },
}

export const IframeFlashBridge: Story = {
  parameters: IframePage.parameters,
  play: async (context) => {
    await IframePage.play!(context)
    const frame = (await within(context.canvasElement).findByTitle('Preview schedule')) as HTMLIFrameElement
    await waitFor(() => expect(frame.contentDocument?.getElementById('apply')).toBeTruthy())
    frame.contentDocument!.getElementById('apply')!.click()
    await expect(await screen.findByText('Schedule applied for the week of Oct 19')).toBeVisible()
  },
}

export const IframeMobile: Story = { parameters: { route: `${author}/actions/preview_schedule`, viewportSize: { width: 390, height: 700 } }, play: IframePage.play }

registerCustomPage('team-board', ({ action }) => (
  <div className="rounded-lg border bg-card p-4">
    <h2 className="text-base font-semibold">{action.label}</h2>
    <p className="mt-1 text-muted-foreground">A host-registered React component rendered by the client.</p>
  </div>
))

const custom = (key: string): Action => ({ ...history, key: 'team_board', label: 'Team board', view: { mode: 'custom', custom_key: key, path: history.view!.path, presentation: 'page' } })

export const CustomComponent: Story = {
  parameters: { route: `${author}/actions/team_board`, viewportSize: { width: 1440, height: 400 }, ...actionsOf(custom('team-board')) },
}

// No component under that key: the ladder falls back to the classic page in a frame.
export const CustomFallsBackToFrame: Story = {
  parameters: { route: `${author}/actions/team_board`, viewportSize: { width: 1440, height: 700 }, ...actionsOf(custom('not-registered')) },
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByText('Lauren Thompson')).toBeVisible()
  },
}

export const UnknownActionIsNotFound: Story = { parameters: { route: `${author}/actions/nope`, viewportSize: { width: 1440, height: 520 } } }
