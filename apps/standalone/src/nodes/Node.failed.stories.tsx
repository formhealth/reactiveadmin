import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, screen, userEvent, within } from 'storybook/test'
import type { Node as NodeData } from '@/api/generated/model'
import { Node } from './Node'

// `error` and `code` are newer than the generated contract, so the samples are typed loosely.
const raw = (node: Record<string, unknown>) => node as unknown as NodeData

const failed = raw({ type: 'error', label: 'SEO plan' })

const code = raw({ type: 'code', language: 'json', text: '{\n  "ref_id": "c-5000",\n  "status": "rejected",\n  "reason": "category is not on file"\n}' })

const longCode = raw({
  type: 'code',
  text: Array.from({ length: 40 }, (_, i) => `line ${i + 1}: ${'0123456789 '.repeat(i % 5 === 0 ? 14 : 3)}`).join('\n'),
})

const meta = {
  title: 'Nodes/Failed and code',
  component: Node,
  parameters: { viewportSize: { width: 720, height: 200 } },
} satisfies Meta<typeof Node>

export default meta
type Story = StoryObj<typeof meta>

export const ErrorValue: Story = { args: { node: failed } }

export const ErrorInTable: Story = {
  args: {
    node: {
      type: 'attributes_table',
      rows: [
        { label: 'Author', value: [{ type: 'text', text: 'Alex Nguyen' }] },
        { label: 'Plan', value: [failed] },
        { label: 'Notes', value: [{ type: 'empty' }] },
      ],
    },
  },
}

export const ErrorTooltip: Story = {
  args: { node: failed },
  play: async ({ canvasElement }) => {
    await userEvent.hover(await within(canvasElement).findByText('SEO plan'))
    await expect(await screen.findByRole('tooltip')).toHaveTextContent("This value couldn't be displayed")
  },
}

export const Code: Story = { args: { node: code }, parameters: { viewportSize: { width: 720, height: 220 } } }

export const CodeWithoutLanguage: Story = { args: { node: raw({ type: 'code', text: 'bundle exec rails runner "Author.count"' }) } }

export const CodeLongScrolls: Story = { args: { node: longCode }, parameters: { viewportSize: { width: 720, height: 480 } } }

export const CodeNarrow: Story = { args: { node: longCode }, parameters: { viewportSize: { width: 360, height: 480 } } }

export const CodeDark: Story = { args: { node: code }, globals: { theme: 'dark' }, parameters: { viewportSize: { width: 720, height: 220 } } }

export const CodeCopy: Story = {
  args: { node: code },
  play: async ({ canvasElement }) => {
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: async () => undefined }, configurable: true })
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Copy to clipboard' }))
    await expect(await within(canvasElement).findByRole('button', { name: 'Copied' })).toBeVisible()
  },
}
