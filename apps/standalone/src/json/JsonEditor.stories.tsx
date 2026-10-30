import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, userEvent, waitFor, within } from 'storybook/test'
import type { FormField, FormResponse } from '@/api/generated/model'
import { RecordForm } from '@/forms/RecordForm'
import { useRecordForm } from '@/forms/useRecordForm'
import { deep, small, withMasked } from './fixtures'

function JsonForm({ field }: { field: Partial<FormField> }) {
  const response: FormResponse = {
    resource: 'demo',
    title: 'Demo',
    action: { method: 'post', path: '/api/admin/demo' },
    permissions: {},
    form: {
      sections: [{ title: null, kind: 'inputs', fields: [{ name: 'details', param: 'demo[details]', label: 'Details', control: 'json', required: false, ...field }] }],
    },
  }
  const form = useRecordForm(response)
  return <RecordForm form={form} onSubmit={(e) => e.preventDefault()} />
}

const story = (field: Partial<FormField>, height = 420): Story => ({
  render: () => <JsonForm field={field} />,
  parameters: { viewportSize: { width: 900, height } },
})

const meta = { title: 'JSON/Editor', parameters: { layout: 'padded' } } satisfies Meta

export default meta
type Story = StoryObj<typeof meta>

export const Valid = story({ value: small, hint: 'Saved as a JSON value' })

export const Deep = story({ value: deep }, 520)

export const Empty = story({ value: null })

export const InvalidText: Story = {
  ...story({ value: small }),
  play: async ({ canvasElement }) => {
    const ui = within(canvasElement)
    await userEvent.click(await ui.findByRole('button', { name: 'Text' }))
    const box = ui.getByRole('textbox')
    await userEvent.clear(box)
    await userEvent.type(box, '{{"publisher": "Acme",\n"active": }', { delay: 0 })
    await ui.findByText(/Invalid JSON: Unexpected token/)
    await expect(ui.getByRole('button', { name: 'Format' })).toHaveProperty('disabled', true)
  },
}

export const TextValid: Story = {
  ...story({ value: small }),
  play: async ({ canvasElement }) => {
    const ui = within(canvasElement)
    await userEvent.click(await ui.findByRole('button', { name: 'Text' }))
    await ui.findByText('Valid JSON')
  },
}

export const TextFormatted: Story = {
  ...story({ value: null }),
  play: async ({ canvasElement }) => {
    const ui = within(canvasElement)
    await userEvent.click(await ui.findByRole('button', { name: 'Text' }))
    await userEvent.type(ui.getByRole('textbox'),'{{"z":1,"a":{{"y":[[1,2]}}', { delay: 0 })
    await userEvent.click(ui.getByRole('button', { name: 'Format' }))
    await expect((ui.getByRole('textbox') as HTMLTextAreaElement).value).toBe('{\n  "z": 1,\n  "a": {\n    "y": [\n      1,\n      2\n    ]\n  }\n}')
  },
}

export const FromTheServerInvalid = story({ value: undefined, errors: ["can't be parsed as JSON"] })

export const Masked = story({ masked: true, value: undefined, hint: 'Credentials' })

export const MaskedValuesInside = story({ value: withMasked })

const summarized: Partial<FormField> = {
  value: null,
  summary: { kind: 'object', keys: ['publisher', 'reader_id', 'group'], size: 3 },
  expand_path: '/admin/posts/5000/_value?field=details',
}
const valueUrl = '/api/admin/posts/5000/_value'

export const Summarized: Story = { ...story(summarized, 220), parameters: { ...story(summarized).parameters, msw: { handlers: [http.get(valueUrl, () => HttpResponse.json({ value: small }))] } } }

const loads = (value: unknown, height = 420): Story => ({
  ...story(summarized, height),
  parameters: { ...story(summarized, height).parameters, msw: { handlers: [http.get(valueUrl, () => HttpResponse.json({ value }))] } },
  play: async ({ canvasElement }) => {
    const ui = within(canvasElement)
    await userEvent.click(await ui.findByRole('button', { name: 'Load to edit' }))
    await waitFor(() => expect(ui.getByText('publisher')).toBeTruthy())
  },
})

export const SummarizedLoaded = loads(small)

export const SummarizedLoadedWithMasked = loads(withMasked)

export const SummarizedForbidden: Story = {
  ...story(summarized, 220),
  parameters: { ...story(summarized).parameters, msw: { handlers: [http.get(valueUrl, () => HttpResponse.json({ code: 'forbidden', message: 'Forbidden' }, { status: 403 }))] } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Load to edit' }))
    await within(canvasElement).findByText("You can't view this value.")
  },
}

export const SummarizedWithoutPath = story({ ...summarized, expand_path: undefined }, 220)

export const Disabled = story({ value: small, disabled: true })

export const DisabledText: Story = {
  ...story({ value: small, disabled: true }),
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Text' }))
  },
}

export const Dark: Story = { ...story({ value: deep }, 520), globals: { theme: 'dark' } }
