import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, within } from 'storybook/test'
import { Node } from '@/nodes/Node'
import { FrameBoundary } from './FrameBoundary'
import { RouteBoundary } from './RouteBoundary'

const Broken = (): never => {
  throw new Error('render failed')
}

const text = (value: string) => ({ type: 'text' as const, text: value })

const meta = {
  title: 'Boundaries',
  parameters: { viewportSize: { width: 900, height: 480 } },
} satisfies Meta

export default meta
type Story = StoryObj<typeof meta>

export const ThrowingNodeAmongSiblings: Story = {
  render: () => (
    <div className="flex flex-col gap-4">
      <Node node={text('Before the broken section')} />
      <Node node={text('Broken')} registry={{ text: Broken }} />
      <Node node={text('After the broken section')} />
    </div>
  ),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getByText("Couldn't display this section")).toBeVisible()
    await expect(canvas.getByRole('link', { name: 'Open in classic admin' })).toHaveAttribute('href', '/admin?classic=1')
    await expect(canvas.getByText('Before the broken section')).toBeVisible()
    await expect(canvas.getByText('After the broken section')).toBeVisible()
  },
}

// A frame whose render throws degrades to the same page as an embedded iframe.
export const FrameFallsBackToIframe: Story = {
  render: () => (
    <FrameBoundary src="/admin/content_plans/1?scope=active" title="Editorial plan">
      <Broken />
    </FrameBoundary>
  ),
  play: async ({ canvasElement }) => {
    const frame = within(canvasElement).getByTitle('Editorial plan')
    await expect(frame.tagName).toBe('IFRAME')
    await expect(frame).toHaveAttribute('src', '/admin/content_plans/1?scope=active&embed=1')
  },
}

export const FrameWithoutSourceShowsChip: Story = {
  render: () => (
    <FrameBoundary>
      <Broken />
    </FrameBoundary>
  ),
  play: async ({ canvasElement }) => {
    await expect(within(canvasElement).getByText("Couldn't display this section")).toBeVisible()
  },
}

export const RouteErrorPage: Story = {
  parameters: { route: '/posts/5001/edit' },
  render: () => (
    <RouteBoundary>
      <Broken />
    </RouteBoundary>
  ),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getByRole('heading', { name: "Couldn't load this page" })).toBeVisible()
    await expect(canvas.getByRole('button', { name: 'Try again' })).toBeVisible()
    await expect(canvas.getByRole('link', { name: 'Open in classic admin' })).toHaveAttribute('href', '/admin/posts/5001/edit?classic=1')
  },
}

export const RouteErrorPageDark: Story = { ...RouteErrorPage, globals: { theme: 'dark' } }
