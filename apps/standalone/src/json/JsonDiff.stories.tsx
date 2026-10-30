import type { Decorator, Meta, StoryObj } from '@storybook/react-vite'
import { expect, userEvent, within } from 'storybook/test'
import type { Node as NodeData } from '@/api/generated/model'
import { IdModeContext } from '@/nodes/context'
import { Node } from '@/nodes/Node'
import { FieldLabelContext } from './context'
import { auditedChanges, deep } from './fixtures'
import { JsonDiff } from './JsonDiff'

const withWidth: Decorator = (Story) => (
  <div className="max-w-3xl">
    <Story />
  </div>
)

const meta = {
  title: 'JSON/Diff',
  component: JsonDiff,
  decorators: [withWidth],
  args: { changes: auditedChanges },
  parameters: { viewportSize: { width: 900, height: 460 } },
} satisfies Meta<typeof JsonDiff>

export default meta
type Story = StoryObj<typeof meta>

export const Inline: Story = { args: { mode: 'inline' } }

export const SideBySide: Story = { args: { mode: 'split' } }

export const SideBySideNarrow: Story = {
  args: { mode: 'split' },
  parameters: { viewportSize: { width: 360, height: 760 } },
}

export const TwoValues: Story = {
  args: { changes: undefined, before: deep, after: { post: { ...deep.post, id: 5001, labels: ['seo-1', 'seo-2'] } } },
}

export const NoChanges: Story = { args: { changes: undefined, before: deep, after: deep } }

export const Dark: Story = { args: { mode: 'split' }, globals: { theme: 'dark' } }

export const RawView: Story = {
  args: { raw: auditedChanges },
  play: async ({ canvasElement }) => {
    await userEvent.click(within(canvasElement).getByRole('button', { name: 'JSON' }))
    await expect(within(canvasElement).getByRole('tree')).toBeTruthy()
  },
}

const auditNode: NodeData = { type: 'json', value: auditedChanges }

export const DetectedOnAShowPage: Story = {
  render: () => (
    <IdModeContext value="full">
      <FieldLabelContext value="Audited changes">
        <Node node={auditNode} />
      </FieldLabelContext>
    </IdModeContext>
  ),
}

export const LookalikeStaysATree: Story = {
  render: () => (
    <IdModeContext value="full">
      <FieldLabelContext value="Tags">
        <Node node={{ type: 'json', value: { tags: ['a', 'b'] } }} />
      </FieldLabelContext>
    </IdModeContext>
  ),
  parameters: { viewportSize: { width: 900, height: 240 } },
}
