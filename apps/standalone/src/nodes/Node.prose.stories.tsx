import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, userEvent, within } from 'storybook/test'
import type { Node as NodeData, NodeMarksItem } from '@/api/generated/model'
import { Node } from './Node'

const text = (value: string, ...marks: NodeMarksItem[]): NodeData => ({ type: 'text', text: value, ...(marks.length && { marks }) })
const link = (label: string, href = '/admin/authors/1/team_history'): NodeData => ({ type: 'link', label, href, external: false })
const para = (...children: NodeData[]): NodeData => ({ type: 'paragraph', children })
const panel = (title: string, ...children: NodeData[]): NodeData => ({ type: 'panel', title, children })
const heading = (level: number, label: string): NodeData => ({ type: 'heading', level, children: [text(label)] })

const meta = {
  title: 'Nodes/Prose',
  component: Node,
  parameters: { layout: 'padded', viewportSize: { width: 640, height: 420 } },
} satisfies Meta<typeof Node>

export default meta
type Story = StoryObj<typeof meta>

export const Headings: Story = {
  args: { node: { type: 'box', children: [1, 2, 3, 4, 5, 6].map((level) => heading(level, `Heading level ${level}`)) } },
  parameters: { viewportSize: { width: 640, height: 360 } },
}

export const InlineMarks: Story = {
  args: {
    node: para(
      text('Plain, '),
      text('strong', 'strong'),
      text(', '),
      text('emphasis', 'em'),
      text(', '),
      text('bin/rails c', 'code'),
      text(', '),
      text('underline', 'underline'),
      text(', '),
      text('struck', 'strike'),
      text(', '),
      text('highlighted', 'mark'),
      text(', '),
      text('small', 'small'),
      text(', H'),
      text('2', 'sub'),
      text('O and x'),
      text('2', 'sup'),
      text(', '),
      text('bold italic', 'strong', 'em'),
      text('.'),
    ),
  },
  parameters: { viewportSize: { width: 640, height: 120 } },
}

export const ParagraphWithLinksBreaksAndAbbr: Story = {
  args: {
    node: para(
      text('Seen by '),
      link('Amelia Chen'),
      text(' on '),
      text('Tuesday', 'strong'),
      { type: 'break' },
      { ...text('SEO', 'strong'), title: 'Search engine optimization' },
      text(' is within range. A much longer sentence follows so the paragraph has to wrap onto a second line at this width, with the spacing intact.'),
    ),
  },
  parameters: { viewportSize: { width: 420, height: 200 } },
}

export const InPanel: Story = {
  args: {
    node: panel(
      'Editor note',
      heading(4, 'Review'),
      para(text('Traffic is '), text('up 2.4%', 'strong'), text(' since the last edit.')),
      { type: 'divider' },
      heading(4, 'Plan'),
      { type: 'blockquote', children: [para(text('Keep the current schedule; '), text('recheck in four weeks', 'em'), text('.'))] },
    ),
  },
  parameters: { viewportSize: { width: 640, height: 360 } },
}

export const Divider: Story = {
  args: { node: { type: 'box', children: [text('Above'), { type: 'divider' }, text('Below')] } },
  parameters: { viewportSize: { width: 400, height: 120 } },
}

export const Blockquote: Story = {
  args: { node: { type: 'blockquote', children: [para(text('Author asked to move the call to '), text('mornings', 'strong'), text('.'))] } },
  parameters: { viewportSize: { width: 500, height: 100 } },
}

const disclosure = (open: boolean): NodeData => ({
  type: 'disclosure',
  open,
  summary_nodes: [text('Raw import '), text('(3 fields)', 'small')],
  children: [para(text('Word count: '), text('1,240', 'strong')), para(text('Reviewed by the team.'))],
})

export const DisclosureClosed: Story = { args: { node: disclosure(false) }, parameters: { viewportSize: { width: 500, height: 100 } } }

export const DisclosureOpen: Story = { args: { node: disclosure(true) }, parameters: { viewportSize: { width: 500, height: 220 } } }

export const DisclosureToggles: Story = {
  args: { node: disclosure(false) },
  parameters: { viewportSize: { width: 500, height: 220 } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.queryByText('Reviewed by the team.')).toBeNull()
    await userEvent.click(canvas.getByRole('button', { name: /Raw import/ }))
    await expect(await canvas.findByText('Reviewed by the team.')).toBeVisible()
  },
}

export const DefinitionList: Story = {
  args: {
    node: {
      type: 'definition_list',
      rows: [
        { label: 'Plan', value: [text('Gold')] },
        { label: 'Notes', value: [text('Prefers mornings'), para(text('Call '), text('after 9am', 'strong'))] },
        { label: 'Fax', value: [{ type: 'empty' }] },
      ],
    },
  },
  parameters: { viewportSize: { width: 640, height: 220 } },
}

export const NestedList: Story = {
  args: {
    node: {
      type: 'list',
      ordered: false,
      children: [
        { type: 'list_item', children: [para(text('Verify '), text('sources', 'strong'))] },
        {
          type: 'list_item',
          children: [text('Schedule intake'), { type: 'list', ordered: true, children: [{ type: 'list_item', children: [text('Call')] }, { type: 'list_item', children: [text('Text')] }] }],
        },
      ],
    },
  },
  parameters: { viewportSize: { width: 500, height: 200 } },
}

export const ProseDark: Story = {
  ...InPanel,
  globals: { theme: 'dark' },
}

export const ProseMobile: Story = {
  args: { node: { type: 'box', children: [heading(2, 'Team history'), InlineMarks.args!.node, disclosure(true)] } },
  parameters: { viewportSize: { width: 360, height: 420 } },
}
