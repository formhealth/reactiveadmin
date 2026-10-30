import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, screen, userEvent, within } from 'storybook/test'
import type { FormResponse } from '@/api/generated/model'
import { cardsPolicyForm, POLICY_ID, policyForm, ROLE_ID, roleForm, STALE_ROW_ID, textPolicyForm } from '@/mocks/nested'
import { ResourceForm } from '@/pages/ResourceForm'

const served = (resource: string, id: string, response: FormResponse) => ({ msw: { handlers: [http.get(`/api/admin/${resource}/${id}/edit`, () => HttpResponse.json(response))] } })

const roleOf = (response: FormResponse) => ({ routePath: ':resource/:id/edit', route: `/admin_roles/${ROLE_ID}/edit`, ...served('admin_roles', ROLE_ID, response) })
const policyOf = (response: FormResponse) => ({ routePath: ':resource/:id/edit', route: `/admin_policies/${POLICY_ID}/edit`, ...served('admin_policies', POLICY_ID, response) })

const meta = {
  title: 'Forms/Nested rows',
  component: ResourceForm,
  args: { mode: 'edit' },
  parameters: { viewportSize: { width: 1000, height: 820 }, ...roleOf(roleForm()) },
} satisfies Meta<typeof ResourceForm>

export default meta
type Story = StoryObj<typeof meta>

const mobile = { viewportSize: { width: 390, height: 844 } }

export const RolePolicies: Story = {}

export const RolePoliciesDark: Story = { globals: { theme: 'dark' } }

export const RolePoliciesMobile: Story = { parameters: { ...mobile, ...roleOf(roleForm()) } }

export const RolePoliciesMobileDark: Story = { globals: { theme: 'dark' }, parameters: { ...mobile, ...roleOf(roleForm()) } }

export const Permissions: Story = { parameters: policyOf(policyForm()) }

const REJECTION = `"legacy_widgets" isn't a registered resource. Choose a permission from the list.`

const rejected = http.patch(`/api/admin/admin_policies/${POLICY_ID}`, () =>
  HttpResponse.json(
    {
      code: 'invalid',
      message: 'Review failed',
      errors: { 'admin_policy_permissions.action': [REJECTION] },
      row_errors: { admin_policy_permissions: [{ id: STALE_ROW_ID, errors: { action: [REJECTION] } }] },
      base: [],
    },
    { status: 422 },
  ),
)

// One of each: a row to remove, a row to add, a duplicate (the 1st and 10th rows), and a row the server rejects.
const reviewed = async (canvasElement: HTMLElement) => {
  const canvas = within(canvasElement)
  await userEvent.click(await canvas.findByRole('button', { name: 'Remove row 5' }))
  await userEvent.click(await canvas.findByRole('combobox', { name: 'Add permission' }))
  await userEvent.type(await screen.findByPlaceholderText('Search permission…'), 'reports')
  await userEvent.click(await screen.findByRole('option', { name: /Reports — index/ }))
  await userEvent.click(await canvas.findByRole('button', { name: 'Save changes' }))
  await expect(await canvas.findByText(/isn't a registered resource/)).toBeVisible()
}

const withReview = { ...policyOf(policyForm()), msw: { handlers: [...policyOf(policyForm()).msw.handlers, rejected] } }

export const PermissionsReview: Story = { parameters: withReview, play: ({ canvasElement }) => reviewed(canvasElement) }

export const PermissionsReviewDark: Story = { ...PermissionsReview, globals: { theme: 'dark' } }

export const PermissionsReviewMobile: Story = { ...PermissionsReview, parameters: { ...withReview, ...mobile } }

export const PermissionsReviewMobileDark: Story = { ...PermissionsReviewMobile, globals: { theme: 'dark' } }

const changeRow2 = async (canvas: ReturnType<typeof within>) => {
  await userEvent.click(await canvas.findByRole('button', { name: /Change permission, row 2/ }))
  await userEvent.keyboard('{Escape}')
}

// One saved row turned into its control, among rows that read as plain values.
export const PermissionsReviewEditing: Story = {
  parameters: withReview,
  play: async ({ canvasElement }) => {
    await reviewed(canvasElement)
    await changeRow2(within(canvasElement))
    await expect(await within(canvasElement).findByRole('combobox', { name: 'Permission, row 2' })).toBeVisible()
  },
}

export const PermissionsReviewEditingDark: Story = { ...PermissionsReviewEditing, globals: { theme: 'dark' } }

export const ChangeSavedRow: Story = {
  parameters: policyOf(policyForm()),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.queryByRole('combobox', { name: 'Permission, row 2' })).toBeNull()
    await changeRow2(canvas)
    await expect(await canvas.findByRole('combobox', { name: 'Permission, row 2' })).toBeVisible()

    // Escape with the picker closed leaves the row as it was.
    await userEvent.keyboard('{Escape}')
    await expect(await canvas.findByRole('button', { name: /Change permission, row 2/ })).toHaveFocus()
    await expect(canvas.queryByText(/Unsaved/)).toBeNull()
  },
}

export const ChangedRowStaysEditable: Story = {
  parameters: policyOf(policyForm()),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click(await canvas.findByRole('button', { name: /Change permission, row 2/ }))
    await userEvent.type(await screen.findByPlaceholderText('Search permission…'), 'reports')
    await userEvent.click(await screen.findByRole('option', { name: /Reports — index/ }))
    await expect(await canvas.findByRole('combobox', { name: 'Permission, row 2' })).toHaveTextContent('Reports — index')
    await userEvent.keyboard('{Escape}')
    await expect(await canvas.findByRole('button', { name: /Change permission, row 2: Comments — show/ })).toBeVisible()
  },
}

export const DuplicateMarksLater: Story = {
  parameters: policyOf(policyForm()),
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findAllByText('Already listed')).toHaveLength(1)
  },
}

export const PendingRemoval: Story = {
  parameters: policyOf(policyForm()),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click(await canvas.findByRole('button', { name: 'Remove row 2' }))
    await expect(await canvas.findByText('Removing')).toBeVisible()
    await expect(await canvas.findByText(/1 to remove/)).toBeVisible()
  },
}

export const Empty: Story = { parameters: policyOf(policyForm({ rows: [] })) }

export const NotDestroyable: Story = { parameters: policyOf(policyForm({ destroy: false, rows: policyForm().form.sections[1].records?.slice(0, 4).map((r) => ({ id: r.id!, value: String(r.fields[1].value) })) })) }

export const MaxRows: Story = { parameters: policyOf(policyForm({ maxRows: 3, rows: policyForm().form.sections[1].records?.slice(0, 3).map((r) => ({ id: r.id!, value: String(r.fields[1].value) })) })) }

export const TextRows: Story = {
  parameters: policyOf(textPolicyForm()),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    const add = await canvas.findByRole('textbox', { name: 'Add permission' })
    await userEvent.type(add, 'resources/tasks/index{Enter}')
    await userEvent.type(add, 'resources/tasks/index{Enter}')
    await expect(await canvas.findByText(/already in the list/)).toBeVisible()
  },
}

export const TextRowsDark: Story = { ...TextRows, globals: { theme: 'dark' } }

export const CardsForMultiControlRows: Story = { parameters: policyOf(cardsPolicyForm()) }

export const CardsForMultiControlRowsDark: Story = { ...CardsForMultiControlRows, globals: { theme: 'dark' } }

export const CardsForMultiControlRowsMobile: Story = { parameters: { ...policyOf(cardsPolicyForm()), ...mobile } }

export const AddPickerOpen: Story = {
  parameters: policyOf(policyForm({ rows: policyForm().form.sections[1].records?.slice(0, 3).map((r) => ({ id: r.id!, value: String(r.fields[1].value) })) })),
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('combobox', { name: 'Add permission' }))
    await userEvent.type(await screen.findByPlaceholderText('Search permission…'), 'authors')
    await expect(await screen.findByRole('option', { name: /Authors — show/ })).toBeVisible()
  },
}
