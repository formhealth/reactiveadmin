import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, fireEvent, screen, userEvent, waitFor, within } from 'storybook/test'
import type { Degradation, FormLock, FormResponse } from '@/api/generated/model'
import { deskForm, desks } from '@/mocks/forms'
import { ResourceForm } from './ResourceForm'

const EDIT = '/api/admin/desks/desk-1/edit'
const SAVE = '/api/admin/desks/desk-1'
const [desk] = desks

const lock = (value: string): FormLock => ({ field: 'lock_version', value })
const edit = (overrides: Partial<FormResponse> = {}) => http.get(EDIT, () => HttpResponse.json({ ...deskForm(desk), ...overrides }))

const meta = {
  title: 'Pages/ResourceForm/Safety',
  component: ResourceForm,
  args: { mode: 'edit' },
  parameters: { routePath: ':resource/:id/edit', route: '/desks/desk-1/edit', viewportSize: { width: 1280, height: 900 } },
} satisfies Meta<typeof ResourceForm>

export default meta
type Story = StoryObj<typeof meta>

const handlers = (...list: ReturnType<typeof http.get>[]) => ({ msw: { handlers: list } })

const degraded: Degradation[] = [{ kind: 'form_partial', where: 'form/section[1]', reason: 'a custom block in this form was replaced with read-only text' }]

export const Degraded: Story = { parameters: handlers(edit({ degraded })) }

export const NotSubmittable: Story = {
  parameters: handlers(edit({ submittable: false, unsupported_reason: 'This form uses a custom partial that has no API equivalent yet.', degraded })),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    const classic = await canvas.findAllByRole('link', { name: /Open in classic admin/ })
    await expect(classic.at(-1)).toHaveAttribute('href', '/admin/desks/desk-1/edit?classic=1')
    await expect(canvas.queryByRole('button', { name: 'Save changes' })).toBeNull()
    await expect(await canvas.findByRole('textbox', { name: /^Name/ })).toBeDisabled()
    await expect(canvas.getByText(/no API equivalent/)).toBeVisible()
  },
}

export const NotSubmittableDark: Story = { ...NotSubmittable, globals: { theme: 'dark' } }

export const NotSubmittableMobile: Story = { ...NotSubmittable, parameters: { ...NotSubmittable.parameters, viewportSize: { width: 390, height: 844 } } }

// The PATCH handler would fail the story if a write got through.
export const NeverWrites: Story = {
  parameters: {
    msw: {
      handlers: [
        edit({ submittable: false }),
        http.patch(SAVE, () => {
          throw new Error('A non-submittable form must not write')
        }),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByRole('textbox', { name: /^Name/ })).toBeDisabled()
    fireEvent.submit(canvasElement.querySelector('form')!)
    await new Promise((resolve) => setTimeout(resolve, 500))
    await expect(canvas.queryByRole('button', { name: /Saving/ })).toBeNull()
    await expect(screen.queryByText(/must not write|Something went wrong/)).toBeNull()
  },
}

const sent: unknown[] = []

export const LockSentWithUpdate: Story = {
  beforeEach: () => {
    sent.length = 0
  },
  parameters: {
    msw: {
      handlers: [
        edit({ lock: lock('3') }),
        http.patch(SAVE, async ({ request }) => {
          sent.push(await request.json())
          return HttpResponse.json({ ok: true, id: 'desk-1', message: 'Desk was successfully updated.', location: { url: '/admin/desks', resource: 'desks', view: 'index' } })
        }),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Save changes' }))
    await waitFor(() => expect(sent).toHaveLength(1))
    await expect(sent[0]).toMatchObject({ lock: { field: 'lock_version', value: '3' } })
  },
}

// The record as it was when the form opened, then as someone else saved it. `latest` flips on the 409.
function staleScenario() {
  let rejected = false
  const opened = { ...deskForm(desk), lock: lock('3') }
  const latest = { ...deskForm({ ...desk, name: 'Features desk (renamed)', region_id: 'region-2' }), lock: lock('4') }
  return {
    reset: () => {
      rejected = false
    },
    handlers: [
      http.get(EDIT, () => {
        const body = rejected ? latest : opened
        rejected = false
        return HttpResponse.json(body)
      }),
      http.patch(SAVE, async ({ request }) => {
        const body = (await request.json()) as { lock?: FormLock }
        if (body.lock?.value !== '4') {
          rejected = true
          return HttpResponse.json({ code: 'stale', message: 'This record was changed by someone else' }, { status: 409 })
        }
        return HttpResponse.json({ ok: true, id: 'desk-1', message: 'Desk was successfully updated.', location: { url: '/admin/desks', resource: 'desks', view: 'index' } })
      }),
    ],
  }
}

const scenario = staleScenario()

const staleStory = (play: Story['play']): Story => ({ beforeEach: scenario.reset, parameters: { msw: { handlers: scenario.handlers } }, play })

const editNameAndSave = async (canvasElement: HTMLElement) => {
  const canvas = within(canvasElement)
  await userEvent.type(await canvas.findByRole('textbox', { name: /^Name/ }), ' east')
  await userEvent.click(canvas.getByRole('button', { name: 'Save changes' }))
  return screen.findByRole('dialog', { name: 'This record changed since you opened it' })
}

export const StalePrompt: Story = staleStory(async ({ canvasElement }) => {
  const dialog = within(await editNameAndSave(canvasElement))
  await expect(dialog.getByRole('button', { name: 'Review changes' })).toBeEnabled()
  await expect(dialog.getByRole('button', { name: 'Discard my changes' })).toBeEnabled()
})

export const StalePromptDark: Story = { ...StalePrompt, globals: { theme: 'dark' } }

const review = async (canvasElement: HTMLElement) => {
  const dialog = await editNameAndSave(canvasElement)
  await userEvent.click(within(dialog).getByRole('button', { name: 'Review changes' }))
  return screen.findByRole('dialog', { name: 'Review changes' })
}

export const StaleReview: Story = staleStory(async ({ canvasElement }) => {
  const dialog = within(await review(canvasElement))
  await expect(dialog.getByText('Features desk (renamed)')).toBeVisible()
  await expect(dialog.getByText('Features desk east')).toBeVisible()
  await expect(dialog.getByText('Also changed by someone else')).toBeVisible()
  await expect(dialog.getByText(/Region/)).toBeVisible()
})

export const StaleReviewMobile: Story = { ...StaleReview, parameters: { ...StaleReview.parameters, viewportSize: { width: 390, height: 844 } } }

export const StaleReapplied: Story = staleStory(async ({ canvasElement }) => {
  const dialog = await review(canvasElement)
  await userEvent.click(within(dialog).getByRole('button', { name: 'Re-apply my changes' }))
  const canvas = within(canvasElement)
  await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
  await expect(await canvas.findByRole('textbox', { name: /^Name/ })).toHaveValue('Features desk east')
  await expect(canvas.getByText('Unsaved changes')).toBeVisible()
  await expect(canvas.getByRole('combobox', { name: /Region/ })).toHaveTextContent('Region 2')
})

// The retry carries the new lock; the mock only accepts it with that.
export const StaleReappliedThenSaved: Story = {
  ...staleStory(async ({ canvasElement }) => {
    await userEvent.click(within(await review(canvasElement)).getByRole('button', { name: 'Re-apply my changes' }))
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Save changes' }))
    // The toast and its live region both carry the message.
    await expect((await screen.findAllByText(/updated/))[0]).toBeVisible()
  }),
}

export const StaleDiscarded: Story = staleStory(async ({ canvasElement }) => {
  const dialog = await editNameAndSave(canvasElement)
  await userEvent.click(within(dialog).getByRole('button', { name: 'Discard my changes' }))
  await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull())
  await expect(await within(canvasElement).findByRole('textbox', { name: /^Name/ })).toHaveValue('Features desk (renamed)')
  await expect(within(canvasElement).queryByText('Unsaved changes')).toBeNull()
})

export const StaleReloadFailed: Story = {
  beforeEach: scenario.reset,
  parameters: {
    msw: {
      handlers: [
        http.get(EDIT, () => HttpResponse.json({ ...deskForm(desk), lock: lock('3') }), { once: true }),
        http.get(EDIT, () => HttpResponse.json({ code: 'error', message: 'Error while rendering desks edit' }, { status: 500 })),
        http.patch(SAVE, () => HttpResponse.json({ code: 'stale', message: 'Changed' }, { status: 409 })),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    const dialog = await editNameAndSave(canvasElement)
    await userEvent.click(within(dialog).getByRole('button', { name: 'Review changes' }))
    await expect(await within(dialog).findByText(/Couldn't load the latest version/)).toBeVisible()
  },
}

export const RateLimitedSave: Story = {
  parameters: {
    msw: {
      handlers: [edit({ lock: lock('3') }), http.patch(SAVE, () => HttpResponse.json({ code: 'rate_limited', message: 'Too many requests' }, { status: 429, headers: { 'Retry-After': '7' } }))],
    },
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Save changes' }))
    await expect(await screen.findByText("You're doing that too fast — try again in 7s")).toBeVisible()
    await expect(within(canvasElement).getByRole('button', { name: 'Save changes' })).toBeEnabled()
  },
}

const busy = () => HttpResponse.json({ code: 'retry', message: 'Another operation was in progress.' }, { status: 409, headers: { 'Retry-After': '1' } })
const saved = () => HttpResponse.json({ ok: true, id: 'desk-1', message: 'Desk was successfully updated.', location: { url: '/admin/desks', resource: 'desks', view: 'index' } })
let writes = 0

// The first write loses a race with a host guard; the form resends it once and never opens the stale dialog.
export const RetryResentOnce: Story = {
  beforeEach: () => {
    writes = 0
  },
  parameters: {
    msw: {
      handlers: [
        edit({ lock: lock('3') }),
        http.patch(SAVE, () => {
          writes += 1
          return writes === 1 ? busy() : saved()
        }),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Save changes' }))
    await expect(await screen.findByText("Couldn't save right now — trying again…")).toBeVisible()
    await waitFor(() => expect(writes).toBe(2), { timeout: 4000 })
    await expect(screen.queryByRole('dialog')).toBeNull()
  },
}

export const RetryFailedTwice: Story = {
  beforeEach: () => {
    writes = 0
  },
  parameters: {
    msw: {
      handlers: [
        edit({ lock: lock('3') }),
        http.patch(SAVE, () => {
          writes += 1
          return busy()
        }),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Save changes' }))
    await expect(await screen.findByRole('button', { name: 'Try again' }, { timeout: 5000 })).toBeVisible()
    await expect(writes).toBe(2)
    await expect(screen.queryByRole('dialog')).toBeNull()
    await expect(within(canvasElement).getByRole('button', { name: 'Save changes' })).toBeEnabled()
  },
}

export const TypeaheadRateLimited: Story = {
  parameters: {
    route: '/desks/desk-2/edit',
    msw: {
      handlers: [http.get('/api/admin/desks/_options', () => HttpResponse.json({ code: 'rate_limited', message: 'Too many requests' }, { status: 429, headers: { 'Retry-After': '20' } }))],
    },
  },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('combobox', { name: /Lead editor/ }))
    await expect(await screen.findByText(/Searching too fast/)).toBeVisible()
  },
}
