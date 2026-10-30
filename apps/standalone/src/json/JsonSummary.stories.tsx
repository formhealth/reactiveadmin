import type { Decorator, Meta, StoryObj } from '@storybook/react-vite'
import { delay, http, HttpResponse } from 'msw'
import { expect, userEvent, waitFor, within } from 'storybook/test'
import type { Node as NodeData } from '@/api/generated/model'
import { IdModeContext, NodeContext } from '@/nodes/context'
import { Node } from '@/nodes/Node'
import { deep, withMasked } from './fixtures'

const expand_path = '/admin/authors/107/_value?field=seo'
const url = '/api/admin/authors/107/_value'

const summarized: NodeData = { type: 'json', summary: { kind: 'object', keys: ['publisher', 'reader_id', 'group'], size: 3 }, expand_path }

const attribute = (label: string, value: NodeData): NodeData => ({ type: 'attributes_table', rows: [{ label, value: [value] }] })

const withPage: Decorator = (Story) => (
  <IdModeContext value="full">
    <div className="max-w-3xl">
      <Story />
    </div>
  </IdModeContext>
)

const meta = {
  title: 'JSON/Summarized node',
  decorators: [withPage],
  render: (args: { node: NodeData }) => <Node node={args.node} />,
  args: { node: attribute('SEO', summarized) },
  parameters: { viewportSize: { width: 900, height: 360 } },
} satisfies Meta<{ node: NodeData }>

export default meta
type Story = StoryObj<typeof meta>

const show = async (canvasElement: HTMLElement) => userEvent.click(await within(canvasElement).findByRole('button', { name: 'Show full value' }))

export const Summary: Story = {
  parameters: { msw: { handlers: [http.get(url, () => HttpResponse.json({ value: withMasked }))] } },
}

export const Expanded: Story = {
  parameters: { msw: { handlers: [http.get(url, () => HttpResponse.json({ value: withMasked }))] }, viewportSize: { width: 900, height: 420 } },
  play: async ({ canvasElement }) => {
    await show(canvasElement)
    await within(canvasElement).findByRole('button', { name: 'Hide value' })
  },
}

export const Loading: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(url, async () => {
          await delay('infinite')
          return HttpResponse.json({ value: deep })
        }),
      ],
    },
  },
  play: async ({ canvasElement }) => {
    await show(canvasElement)
    await waitFor(() => expect(within(canvasElement).getByRole('button', { name: 'Loading' })).toHaveProperty('disabled', true))
  },
}

export const Forbidden: Story = {
  parameters: { msw: { handlers: [http.get(url, () => HttpResponse.json({ code: 'forbidden', message: 'Not allowed' }, { status: 403 }))] } },
  play: async ({ canvasElement }) => {
    await show(canvasElement)
    await within(canvasElement).findByText("You don't have access to this value.")
  },
}

export const Failed: Story = {
  parameters: { msw: { handlers: [http.get(url, () => HttpResponse.json({ code: 'error', message: 'Boom' }, { status: 500 }))] } },
  play: async ({ canvasElement }) => {
    await show(canvasElement)
    await within(canvasElement).findByText("Couldn't load the value. Try again.")
    expect(within(canvasElement).getByRole('button', { name: 'Try again' })).toBeTruthy()
  },
}

export const ManyKeys: Story = {
  args: { node: attribute('Payload', { ...summarized, summary: { kind: 'object', keys: Array.from({ length: 12 }, (_, i) => `field_${i + 1}`), size: 12 } }) },
}

export const ArraySummary: Story = {
  args: { node: attribute('History', { type: 'json', summary: { kind: 'array', keys: [], size: 240 }, expand_path }) },
}

export const TableCell: Story = {
  render: () => (
    <IdModeContext value="short">
      <Node node={summarized} />
    </IdModeContext>
  ),
  parameters: { viewportSize: { width: 600, height: 200 } },
}

const changes: NodeData = { type: 'json', summary: { kind: 'object', keys: ['publisher', 'reader_id'], size: 2 } }

export const WithoutExpandPath: Story = {
  args: { node: attribute('Changes', changes) },
  parameters: { route: '/authors/107' },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    expect(canvas.queryByRole('button', { name: 'Show full value' })).toBeNull()
    expect(canvas.getByText('Full value available in the classic admin')).toBeTruthy()
    expect(canvas.getByRole('link', { name: 'Open in classic admin' }).getAttribute('href')).toBe('/admin/authors/107?classic=1')
  },
}

export const WithoutExpandPathInRecord: Story = {
  args: { node: attribute('Changes', changes) },
  render: (args) => (
    <NodeContext value={{ resource: 'audit_trails', id: '42' }}>
      <Node node={args.node} />
    </NodeContext>
  ),
  play: async ({ canvasElement }) => {
    expect(within(canvasElement).getByRole('link', { name: 'Open in classic admin' }).getAttribute('href')).toBe('/admin/audit_trails/42?classic=1')
  },
}

export const Dark: Story = { globals: { theme: 'dark' }, parameters: { msw: { handlers: [http.get(url, () => HttpResponse.json({ value: withMasked }))] } } }
