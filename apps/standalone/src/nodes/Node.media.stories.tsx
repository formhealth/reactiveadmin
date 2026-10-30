import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import type { Decorator, Meta, StoryObj } from '@storybook/react-vite'
import { expect, screen, userEvent, waitFor, within } from 'storybook/test'
import { getGetManifestQueryKey } from '@/api/generated/core'
import type { Node as NodeData } from '@/api/generated/model'
import { manifestBody } from '@/mocks/handlers'
import { Node } from './Node'

const TRUSTED_HOST = 'cdn.example.test'

// The shell's manifest names the hosts media may load from; stories seed it the same way the app does.
function TrustedHosts({ hosts, children }: { hosts: string[]; children: React.ReactNode }) {
  const client = useQueryClient()
  useState(() => client.setQueryData(getGetManifestQueryKey(), { ...manifestBody, site: { ...manifestBody.site, trusted_media_hosts: hosts } }))
  return children
}

const withTrustedHost: Decorator = (Story) => (
  <TrustedHosts hosts={[TRUSTED_HOST]}>
    <Story />
  </TrustedHosts>
)

const image: NodeData = { type: 'image', src: '/mocks/scan.svg', alt: 'Scanned report, page 1', width_px: 320, height_px: 400 }
const pdf: NodeData = { type: 'document', src: '/mocks/report.pdf', mime: 'application/pdf', title: 'Annual report, Oct 14' }

const meta = {
  title: 'Nodes/Media',
  component: Node,
  decorators: [withTrustedHost],
  parameters: { viewportSize: { width: 900, height: 520 } },
} satisfies Meta<typeof Node>

export default meta
type Story = StoryObj<typeof meta>

export const Image: Story = {
  args: { node: image },
  play: async ({ canvasElement }) => {
    const img = await within(canvasElement).findByAltText('Scanned report, page 1')
    await expect(img).toHaveAttribute('referrerpolicy', 'no-referrer')
    await expect(img).toHaveAttribute('loading', 'lazy')
  },
}

export const ImageDark: Story = { ...Image, globals: { theme: 'dark' } }

export const ImageLightbox: Story = {
  args: { node: image },
  parameters: { viewportSize: { width: 1000, height: 760 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'View larger: Scanned report, page 1' }))
    const dialog = await screen.findByRole('dialog', { name: 'Scanned report, page 1' })
    await expect(within(dialog).getByText('Fit')).toBeVisible()
    await expect(within(dialog).getByRole('link', { name: 'Open in new tab' })).toHaveAttribute('rel', 'noopener noreferrer')
  },
}

export const ImageLightboxZoomed: Story = {
  args: { node: image },
  parameters: { viewportSize: { width: 1000, height: 760 } },
  play: async (context) => {
    await ImageLightbox.play?.(context)
    const dialog = await screen.findByRole('dialog')
    await waitFor(() => expect(within(dialog).getByRole('img')).toHaveProperty('complete', true))
    await userEvent.keyboard('{+}')
    await expect(within(dialog).getByText('100%')).toBeVisible()
    await userEvent.keyboard('{+}')
    await expect(within(dialog).getByText('150%')).toBeVisible()
    await userEvent.keyboard('0')
    await expect(within(dialog).getByText('Fit')).toBeVisible()
  },
}

export const ImageFromTrustedHostFailsToLoad: Story = {
  args: { node: { type: 'image', src: `https://${TRUSTED_HOST}/missing/?token=expired`, alt: 'Cover image, front' } },
  play: async ({ canvasElement }) => {
    await waitFor(() => expect(within(canvasElement).getByText(/couldn't be loaded/)).toBeVisible(), { timeout: 4000 })
    await expect(within(canvasElement).getByRole('link', { name: 'Open it in a new tab' })).toBeVisible()
  },
}

export const Document: Story = {
  args: { node: pdf },
  parameters: { viewportSize: { width: 900, height: 560 } },
  play: async ({ canvasElement }) => {
    const frame = await within(canvasElement).findByTitle('Annual report, Oct 14')
    await expect(frame).toHaveAttribute('referrerpolicy', 'no-referrer')
    await expect(within(canvasElement).getByRole('link', { name: /Open in new tab/ })).toHaveAttribute('href', '/mocks/report.pdf')
    await expect(within(canvasElement).getByRole('link', { name: /Download/ })).toHaveAttribute('download')
  },
}

export const DocumentDark: Story = { ...Document, globals: { theme: 'dark' } }

export const DocumentMobile: Story = { ...Document, parameters: { viewportSize: { width: 390, height: 560 } } }

export const DocumentWithoutTitle: Story = { args: { node: { ...pdf, title: undefined } } }

export const OnAShowPage: Story = {
  args: {
    node: {
      type: 'attributes_table',
      title: 'Source document',
      rows: [
        { label: 'Type', value: [{ type: 'text', text: 'Attachment' }] },
        { label: 'Scan', value: [image] },
        { label: 'PDF', value: [pdf] },
      ],
    },
  },
  parameters: { viewportSize: { width: 1000, height: 1200 } },
}

const blocked = (...nodes: NodeData[]): Story => ({
  args: { node: { type: 'group', children: [{ type: 'text', text: 'Rejected media renders as nothing:' }, ...nodes] } },
  play: async ({ canvasElement }) => {
    await expect(canvasElement.querySelector('img, iframe, object, embed, a[href^="javascript:"]')).toBeNull()
  },
})

export const BlockedImages = blocked(
  { type: 'image', src: 'https://evil.example/pixel.png', alt: 'Tracker' },
  { type: 'image', src: 'data:image/png;base64,iVBORw0KGgo=', alt: 'Inline' },
  { type: 'image', src: 'javascript:alert(1)', alt: 'Script' },
  { type: 'image', src: '//cdn.example.test/protocol-relative.png', alt: 'Protocol relative' },
  { type: 'image', src: `https://user:pass@${TRUSTED_HOST}/a.png`, alt: 'Credentials' },
)

export const BlockedDocuments = blocked(
  { type: 'document', src: 'https://evil.example/a.pdf', mime: 'application/pdf' },
  { type: 'document', src: 'data:application/pdf;base64,AA==', mime: 'application/pdf' },
  { type: 'document', src: 'javascript:alert(1)', mime: 'application/pdf' },
  // Newer servers may send other types; only PDF is embedded.
  { type: 'document', src: '/mocks/report.pdf', mime: 'text/html' } as unknown as NodeData,
)

export const NoTrustedHostsUntilTheManifestLoads: Story = {
  decorators: [(Story) => <TrustedHosts hosts={[]}>{<Story />}</TrustedHosts>],
  args: { node: { type: 'image', src: `https://${TRUSTED_HOST}/a/`, alt: 'Not yet trusted' } },
  play: async ({ canvasElement }) => {
    await expect(canvasElement.querySelector('img')).toBeNull()
  },
}
