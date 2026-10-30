import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, within } from 'storybook/test'
import type { FormField, FormResponse, Node } from '@/api/generated/model'
import { ResourceForm } from './ResourceForm'

const NEW = '/api/admin/desks/new'

const text = (value: string, marks?: ('strong' | 'em')[]): Node => ({ type: 'text', text: value, ...(marks && { marks }) })
const heading = (value: string, marks?: ('strong' | 'em')[]): Node => ({ type: 'heading', level: 3, children: [text(value, marks)] })
const row = (label: string, ...value: Node[]) => ({ label, value })

const field = (name: string, extra: Partial<FormField> = {}): FormField => ({ name, param: `desk[${name}]`, label: name, control: 'select', required: false, ...extra })
const content = (name: string, layout: Node[]): FormField => ({ name, param: null, label: '', control: 'content', required: false, layout })

const plans = [
  { label: 'Standard monthly', value: '1' },
  { label: 'Premium monthly', value: '2' },
]

// The shape of a "new plan" form wrapped in the record's context: a heading, a table of the current plan,
// the title of the panel around the inputs, and a note between two inputs.
const withPlan: FormResponse = {
  resource: 'desks',
  title: 'New billing account',
  action: { method: 'post', path: '/api/admin/desks' },
  permissions: { create: true },
  form: {
    sections: [
      {
        kind: 'inputs',
        fields: [
          content('content_1', [
            heading('Jordan Johnson', ['strong']),
            {
              type: 'box',
              tag: 'div',
              children: [
                {
                  type: 'panel',
                  title: 'Current Plan',
                  children: [
                    {
                      type: 'attributes_table',
                      rows: [
                        row('Category', text('Acme Media')),
                        row('Billing plan', text('Standard monthly')),
                        row('Stripe customer', { type: 'masked' }),
                        row('Manage', { type: 'link', label: 'Open in Stripe', href: 'https://dashboard.stripe.com/customers', external: true }),
                      ],
                    },
                  ],
                },
                heading('New Plan'),
              ],
            },
          ]),
        ],
      },
      {
        kind: 'inputs',
        fields: [
          field('billing_plan_id', { label: 'Billing plan', required: true, options: plans }),
          content('content_2', [{ type: 'text', text: 'The new plan starts on the next invoice.' }]),
          field('category_id', { label: 'Category', options: [{ label: 'Acme Media', value: '1' }] }),
        ],
      },
    ],
  },
}

const withoutPlan: FormResponse = {
  ...withPlan,
  form: { sections: [{ kind: 'inputs', fields: [content('content_1', [heading('Jordan Johnson', ['strong']), { type: 'text', text: 'Current billing account required' }])] }] },
}

const meta = {
  title: 'Pages/ResourceForm/Content',
  component: ResourceForm,
  args: { mode: 'new' },
  parameters: { routePath: ':resource/new', route: '/desks/new', viewportSize: { width: 1280, height: 760 } },
} satisfies Meta<typeof ResourceForm>

export default meta
type Story = StoryObj<typeof meta>

const serving = (response: FormResponse) => ({ msw: { handlers: [http.get(NEW, () => HttpResponse.json(response))] } })

export const BillingAccount: Story = {
  parameters: serving(withPlan),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByRole('heading', { name: 'Jordan Johnson' })).toBeVisible()
    await expect(canvas.getByText('Current Plan')).toBeVisible()
    await expect(canvas.getByRole('heading', { name: 'New Plan' })).toBeVisible()
    await expect(canvas.getByText('The new plan starts on the next invoice.')).toBeVisible()
    await expect(canvas.getByRole('button', { name: /Create/ })).toBeEnabled()
  },
}

export const BillingAccountDark: Story = { ...BillingAccount, globals: { theme: 'dark' } }

export const BillingAccountMobile: Story = { ...BillingAccount, parameters: { ...BillingAccount.parameters, viewportSize: { width: 390, height: 844 } } }

export const NoCurrentPlan: Story = {
  parameters: serving(withoutPlan),
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByText('Current billing account required')).toBeVisible()
  },
}
