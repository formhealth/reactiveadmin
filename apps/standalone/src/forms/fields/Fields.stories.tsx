import type { Meta, StoryObj } from '@storybook/react-vite'
import { userEvent, within } from 'storybook/test'
import type { FormField, FormResponse } from '@/api/generated/model'
import { RecordForm } from '../RecordForm'
import { useRecordForm } from '../useRecordForm'

type Base = Partial<FormField> & Pick<FormField, 'control'>

const STATES = ['Default', 'Filled', 'Error', 'Disabled'] as const

function Variants({ base, filled, error = 'Enter a valid value' }: { base: Base; filled: Partial<FormField>; error?: string }) {
  const field = (state: (typeof STATES)[number]): FormField => {
    const key = state.toLowerCase()
    const extra: Record<string, Partial<FormField>> = {
      default: {},
      filled,
      error: { ...filled, errors: [error] },
      disabled: { ...filled, disabled: true },
    }
    return { name: key, param: `demo[${key}]`, label: 'Label', required: false, ...base, ...extra[key] }
  }
  const response: FormResponse = {
    resource: 'demo',
    title: 'Demo',
    action: { method: 'post', path: '/api/admin/demo' },
    permissions: {},
    form: { sections: STATES.map((title) => ({ title, kind: 'inputs', fields: [field(title)] })) },
  }
  const form = useRecordForm(response)
  return <RecordForm form={form} onSubmit={(e) => e.preventDefault()} className="grid items-start gap-4 lg:grid-cols-2" />
}

const meta = {
  title: 'Forms/Fields',
  parameters: { layout: 'padded', viewportSize: { width: 1280, height: 420 } },
} satisfies Meta

export default meta
type Story = StoryObj<typeof meta>

const variants = (base: Base, filled: Partial<FormField>, error?: string, height = 420): Story => ({
  render: () => <Variants base={base} filled={filled} error={error} />,
  parameters: { viewportSize: { width: 1280, height } },
})

const editors = [
  { label: 'Amelia Chen', value: '1' },
  { label: 'Marcus Webb', value: '2' },
  { label: 'Priya Raman', value: '3' },
]

export const Text = variants({ control: 'text', label: 'Author name', placeholder: 'e.g. Alex Nguyen', hint: 'As it appears in the byline', required: true }, { value: 'Alex Nguyen' }, "Can't be blank")

export const Textarea = variants({ control: 'textarea', label: 'Notes', input_html: { rows: 3 }, hint: 'Visible to the team' }, { value: 'Author prefers morning calls.\nFollow up on attachments.' }, 'Is too long (maximum 500 characters)', 560)

export const Numeric = variants({ control: 'number', label: 'Rating', input_html: { min: 1, max: 5, step: 0.1 } }, { value: 4.2 }, 'Enter a number from 1 to 5')

export const Email = variants({ control: 'email', label: 'Email', placeholder: 'name@example.com' }, { value: 'alex.nguyen@example.com' }, 'Enter a valid email address')

export const Url = variants({ control: 'url', label: 'Publisher URL', placeholder: 'https://' }, { value: 'https://publisher.example.com/posts/5001' }, 'Enter a valid URL, including https://')

export const Phone = variants({ control: 'phone', label: 'Phone' }, { value: '(617) 555-0142' }, 'Enter a valid phone number')

export const Password = variants({ control: 'password', label: 'New password', hint: 'At least 12 characters' }, { value: 'correct horse battery' }, 'Is too short (minimum is 12 characters)')

export const Select = variants({ control: 'select', label: 'Region', options: [{ label: 'Region 1', value: '1' }, { label: 'Region 2', value: '2' }], placeholder: 'Select a region' }, { value: '2' }, 'Must exist')

export const Multiselect = variants({ control: 'multiselect', label: 'Editors', multiple: true, options: editors }, { value: ['1', '3'] }, 'Choose at least one editor', 560)

export const Typeahead = variants(
  {
    control: 'typeahead',
    label: 'Editor',
    placeholder: 'Search editors…',
    options_path: '/api/admin/posts/_options?field=editor&context=form',
  },
  { value: '2', options: [editors[1]] },
  'Must exist',
)

const authorField: Base = {
  control: 'typeahead',
  label: 'Author',
  placeholder: 'Search authors…',
  hint: 'Search by name, or paste an author id',
  options_path: '/api/admin/posts/_options?field=author&context=form',
}

function TypeaheadOnly({ field }: { field: FormField }) {
  const response: FormResponse = {
    resource: 'demo',
    title: 'Demo',
    action: { method: 'post', path: '/api/admin/demo' },
    permissions: {},
    form: { sections: [{ title: null, kind: 'inputs', fields: [field] }] },
  }
  const form = useRecordForm(response)
  return <RecordForm form={form} onSubmit={(e) => e.preventDefault()} />
}

const typeahead = (field: Partial<FormField>, play?: Story['play'], height = 560): Story => ({
  render: () => <TypeaheadOnly field={{ name: 'author', param: 'demo[author_id]', required: false, ...authorField, ...field } as FormField} />,
  parameters: { viewportSize: { width: 720, height } },
  play,
})

const openPicker = async (canvasElement: HTMLElement) => {
  await userEvent.click(await within(canvasElement).findByRole('combobox'))
  await within(document.body).findByPlaceholderText(/Search/)
}

export const TypeaheadWithHints: Story = typeahead({ value: '100', options: [] }, async ({ canvasElement }) => {
  await openPicker(canvasElement)
  await within(document.body).findByText('jordan.tanaka1@example.com')
})

export const TypeaheadLoadMore: Story = typeahead({}, async ({ canvasElement }) => {
  await openPicker(canvasElement)
  const more = await within(document.body).findByText('Load more')
  more.scrollIntoView()
})

export const TypeaheadRecentSelections: Story = {
  ...typeahead({}, async ({ canvasElement }) => {
    await openPicker(canvasElement)
    await within(document.body).findByText('Recent')
  }),
  parameters: {
    viewportSize: { width: 720, height: 560 },
    storage: { 'ra:options:/api/admin/posts/_options|author|form': ['104', '112'] },
  },
}

export const TypeaheadSearching: Story = typeahead({}, async ({ canvasElement }) => {
  await openPicker(canvasElement)
  await userEvent.type(within(document.body).getByPlaceholderText(/Search/), 'sam')
  await within(document.body).findByText('Sam Voss')
})

export const TypeaheadMultiple: Story = typeahead({ control: 'multiselect', multiple: true, label: 'Authors', value: ['100', '103'], options: [] }, async ({ canvasElement }) => {
  await openPicker(canvasElement)
  await within(document.body).findByText('Selected')
})

export const MaskedSecret = variants({ control: 'text', label: 'Webhook secret', masked: true, hint: 'Leave blank to keep the current secret' }, {}, "Can't be blank", 420)

export const Radio = variants({ control: 'radio', label: 'Publication status', options: [{ label: 'Pending', value: 'pending' }, { label: 'Published', value: 'published' }, { label: 'Rejected', value: 'rejected' }] }, { value: 'published' }, 'Choose a status', 600)

export const Checkboxes = variants({ control: 'checkboxes', label: 'Notify', options: [{ label: 'Author', value: 'author' }, { label: 'Team', value: 'team' }, { label: 'Billing', value: 'billing' }] }, { value: ['author', 'billing'] }, 'Choose at least one', 600)

export const Toggle = variants({ control: 'boolean', label: 'SEO checked', hint: 'Turn on once indexing is confirmed' }, { value: true }, 'Must be checked before publishing')

export const DatePicker = variants({ control: 'date', label: 'Published on', required: true }, { value: '2026-10-13' }, "Can't be blank")

const dateRange = (field: Partial<FormField>): Story => ({
  render: () => <TypeaheadOnly field={{ name: 'service', param: 'demo[service]', label: 'Published on', required: false, ...field } as FormField} />,
  parameters: { viewportSize: { width: 720, height: 480 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Published on/ }))
    await within(document.body).findByRole('grid')
  },
})

export const DatePickerLimited = dateRange({ control: 'date', value: '2026-10-15', hint: 'Within the publishing window', input_html: { min: '2026-10-10', max: '2026-10-22' } })

export const DateTimeLimited = dateRange({ control: 'datetime', value: '2026-10-20T14:30:00Z', input_html: { min: '2026-10-12T00:00:00Z' } })

export const DateTime = variants({ control: 'datetime', label: 'Scheduled at' }, { value: '2026-10-20T14:30' }, 'Must be in the future')

export const Time = variants({ control: 'time', label: 'Reminder time' }, { value: '09:30' }, 'Is not a valid time')

export const Json = variants(
  { control: 'json', label: 'Details', hint: 'Enter valid JSON', input_html: { rows: 5 } },
  { value: { author_state: 'MA', tags: ['news'] } },
  'author_state must be a two-letter code',
  760,
)

export const Upload = variants({ control: 'file', label: 'Consent form', hint: 'PDF up to 10 MB' }, { value: '/uploads/consent-5001.pdf' }, 'Must be a PDF')

export const Html = variants({ control: 'html', label: 'Rendered summary' }, { value: '<p><strong>SEO check</strong> cached for 24h.</p><ul><li>Indexing: allowed</li></ul>' })
