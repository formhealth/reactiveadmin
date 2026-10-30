import type { Meta, StoryObj } from '@storybook/react-vite'
import { userEvent, within } from 'storybook/test'
import type { FormResponse } from '@/api/generated/model'
import { deskForm, desks } from '@/mocks/forms'
import { RecordForm } from './RecordForm'
import { useRecordForm } from './useRecordForm'

function Harness({ response }: { response: FormResponse }) {
  const form = useRecordForm(response)
  return <RecordForm form={form} onSubmit={(e) => e.preventDefault()} />
}

const meta = {
  title: 'Forms/HasMany',
  component: Harness,
  args: { response: deskForm() },
  parameters: { viewportSize: { width: 1100, height: 760 } },
} satisfies Meta<typeof Harness>

export default meta
type Story = StoryObj<typeof meta>

export const Empty: Story = {}

export const WithRecords: Story = { args: { response: deskForm(desks[0]) } }

export const MarkedForDeletion: Story = {
  args: { response: deskForm(desks[0]) },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Remove row 1' }))
  },
}

export const NewRowAdded: Story = {
  args: { response: deskForm(desks[0]) },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Add member' }))
  },
}

const sortable = deskForm(desks[0])
sortable.form.sections[1] = { ...sortable.form.sections[1], title: 'Ordered members', sortable: 'position' }

export const Sortable: Story = { args: { response: sortable } }
