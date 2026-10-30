import type { Decorator, Meta, StoryObj } from '@storybook/react-vite'
import type { Node as NodeData, NodeVariant } from '@/api/generated/model'
import { NodeContext } from './context'
import { Node } from './Node'

const withRecord: Decorator = (Story) => (
  <NodeContext value={{ resource: 'posts', id: '5000' }}>
    <Story />
  </NodeContext>
)

const text = (value: string): NodeData => ({ type: 'text', text: value })
const status = (variant: NodeVariant, label: string = variant): NodeData => ({ type: 'status', label, variant })
const author: NodeData = { type: 'ref', label: 'Alex Nguyen', ref: { resource: 'authors', id: '107' } }

const json: NodeData = {
  type: 'json',
  value: { publisher: 'Acme Media', indexing: { active: true, price_cents: 3500 }, plans: [{ code: 'WEB-1', primary: true }] },
}

const html: NodeData = {
  type: 'html',
  html: '<p><strong>Notes:</strong> SEO check <em>cached</em> for 24h.</p><ul><li>Indexing: allowed</li><li>Sitemap: included</li></ul>',
}

const attributesTable: NodeData = {
  type: 'attributes_table',
  title: 'Post',
  rows: [
    { label: 'ID', value: [text('5000')] },
    { label: 'Author', value: [author] },
    { label: 'Publication Status', value: [status('success', 'Published')] },
    { label: 'Created At', value: [{ type: 'datetime', value: '2026-10-14T09:30:00Z' }] },
  ],
}

const table: NodeData = {
  type: 'table',
  headers: ['ID', 'Author', 'Status', 'Checked'],
  rows: [
    [text('5000'), author, status('success', 'Published'), { type: 'boolean', value: true }],
    [text('5001'), { ...author, label: 'Jordan Patel' }, status('danger', 'Review failed'), { type: 'boolean', value: false }],
    [text('5002'), { ...author, label: 'Sam Garcia' }, status('warning', 'Rejected'), { type: 'boolean', value: true }],
  ],
}

const statuses = (['neutral', 'success', 'warning', 'danger', 'info'] as const).map((variant) => status(variant))

const samples: Record<string, NodeData> = {
  Empty: { type: 'empty' },
  Text: text('Plain text value'),
  Number: { type: 'number', value: 1234567.5 },
  Boolean: { type: 'group', children: [{ type: 'boolean', value: true }, { type: 'boolean', value: false }] },
  Date: { type: 'date', value: '2026-10-14' },
  DateTime: { type: 'datetime', value: '2026-10-14T09:30:00Z' },
  Ref: author,
  LinkInternal: { type: 'link', label: 'Author record', href: '/authors/107', ref: { resource: 'authors', id: '107' } },
  LinkExternal: { type: 'link', label: 'ref-5000', href: 'https://example.com/refs/5000', external: true },
  StatusVariants: { type: 'group', children: statuses },
  Json: json,
  Html: html,
  Group: { type: 'group', children: [author, status('info', 'Checked'), text('3 views')] },
  Box: { type: 'box', tag: 'div', class_name: 'columns', children: [text('First child'), text('Second child'), author] },
  Panel: { type: 'panel', title: 'SEO Data', children: [status('info', 'Checked'), json] },
  AttributesTable: attributesTable,
  Table: table,
}

const meta = {
  title: 'Nodes',
  component: Node,
  parameters: { viewportSize: { width: 720, height: 320 } },
} satisfies Meta<typeof Node>

export default meta
type Story = StoryObj<typeof meta>

const story = (name: keyof typeof samples, extra: Omit<Story, 'args'> = {}): Story => ({ args: { node: samples[name] }, ...extra })

export const Empty = story('Empty')
export const TextNode = story('Text')
export const NumberNode = story('Number')
export const BooleanNode = story('Boolean')
export const DateNode = story('Date')
export const DateTimeNode = story('DateTime')
export const RefNode = story('Ref')
export const LinkInternal = story('LinkInternal')
export const LinkExternal = story('LinkExternal')
export const StatusVariants = story('StatusVariants')
export const JsonNode = story('Json', { parameters: { viewportSize: { width: 720, height: 160 } } })
export const HtmlWithClassicLink = story('Html', {
  decorators: [withRecord],
})
export const GroupNode = story('Group')
export const BoxNode = story('Box')
export const PanelNode = story('Panel', { parameters: { viewportSize: { width: 720, height: 420 } } })
export const AttributesTableNode = story('AttributesTable', { parameters: { viewportSize: { width: 720, height: 340 } } })
export const TableNode = story('Table', { parameters: { viewportSize: { width: 720, height: 280 } } })

export const TableRepeatedHeaders: Story = {
  args: {
    node: {
      type: 'table',
      headers: ['Name', 'Date', 'Date', ''],
      rows: [[text('Intake'), { type: 'date', value: '2026-10-01' }, { type: 'date', value: '2026-10-14' }, text('Done')]],
    },
  },
  parameters: { viewportSize: { width: 720, height: 140 } },
}

export const AllNodes: Story = {
  args: {
    node: {
      type: 'attributes_table',
      title: 'All node types',
      rows: Object.entries(samples).map(([label, node]) => ({ label, value: [node] })),
    },
  },
  decorators: [withRecord],
  parameters: { viewportSize: { width: 1024, height: 1280 } },
}
