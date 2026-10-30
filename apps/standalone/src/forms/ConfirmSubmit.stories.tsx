import { useState } from 'react'
import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, screen, userEvent, within } from 'storybook/test'
import type { FormResponse } from '@/api/generated/model'
import { deskForm, desks } from '@/mocks/forms'
import { RecordForm, SubmitButton } from './RecordForm'
import { useRecordForm } from './useRecordForm'

function Harness({ response }: { response: FormResponse }) {
  const form = useRecordForm(response)
  const [sent, setSent] = useState(0)
  return (
    <RecordForm form={form} onSubmit={form.submit(async () => undefined, () => setSent((n) => n + 1))}>
      <SubmitButton form={form} label={response.submit_label ?? 'Save'} />
      <p>Sent: {sent}</p>
    </RecordForm>
  )
}

const meta = {
  title: 'Forms/ConfirmSubmit',
  component: Harness,
  args: { response: { ...deskForm(desks[0]), submit_label: 'Archive desk', submit_confirm: 'Archive this desk and release its members?' } },
  parameters: { viewportSize: { width: 900, height: 900 } },
} satisfies Meta<typeof Harness>

export default meta
type Story = StoryObj<typeof meta>

const submit = (canvasElement: HTMLElement) => userEvent.click(within(canvasElement).getByRole('button', { name: 'Archive desk' }))

export const Asks: Story = {
  play: async ({ canvasElement }) => {
    await submit(canvasElement)
    await expect(await screen.findByRole('alertdialog', { name: 'Archive desk' })).toBeInTheDocument()
  },
}

export const DeclinedSendsNothing: Story = {
  play: async ({ canvasElement }) => {
    await submit(canvasElement)
    await userEvent.click(await screen.findByRole('button', { name: 'Cancel' }))
    await expect(within(canvasElement).getByText('Sent: 0')).toBeInTheDocument()
  },
}

export const AcceptedSends: Story = {
  play: async ({ canvasElement }) => {
    await submit(canvasElement)
    const dialog = await screen.findByRole('alertdialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Archive desk' }))
    await expect(await within(canvasElement).findByText('Sent: 1')).toBeInTheDocument()
  },
}
