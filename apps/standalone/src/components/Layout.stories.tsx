import type { Meta, StoryObj } from '@storybook/react-vite'
import { delay, http, HttpResponse } from 'msw'
import { expect, screen, userEvent, within } from 'storybook/test'
import type { Manifest } from '@/api/generated/model'
import { session } from '@/mocks/forms'
import { apiError, manifestBody } from '@/mocks/handlers'
import { AppRoutes } from '@/AppRoutes'

const meta = {
  title: 'Layout',
  component: AppRoutes,
  parameters: { layout: 'fullscreen', route: '/posts', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof AppRoutes>

export default meta
type Story = StoryObj<typeof meta>

const manifest = (override: (m: Manifest) => Manifest) => ({ msw: { handlers: [http.get('/api/admin/_manifest', () => HttpResponse.json(override(manifestBody)))] } })

// The server says this user may switch between the classic admin and this client.
const switchable = { msw: { handlers: [http.get('/api/admin/_session', () => HttpResponse.json({ ...session, ui: { available: true, default: 'classic' } }))] } }

export const GroupedSidebar: Story = {}

export const Home: Story = { parameters: { route: '/' } }

export const HomeWithUiSwitch: Story = {
  parameters: { route: '/', ...switchable, viewportSize: { width: 1280, height: 520 } },
  play: async ({ canvasElement }) => {
    await expect(await within(canvasElement).findByRole('button', { name: 'Use classic admin' })).toBeVisible()
  },
}

export const HomeWithoutUiSwitch: Story = {
  parameters: {
    route: '/',
    msw: { handlers: [http.get('/api/admin/_session', () => HttpResponse.json({ ...session, ui: { available: false, default: 'classic' } }))] },
    viewportSize: { width: 1280, height: 520 },
  },
  play: async ({ canvasElement }) => {
    await within(canvasElement).findByText('Welcome')
    await new Promise((resolve) => setTimeout(resolve, 100))
    await expect(within(canvasElement).queryByRole('button', { name: 'Use classic admin' })).toBeNull()
  },
}

export const HomeRedirectsToResource: Story = {
  parameters: { route: '/', ...manifest((m) => ({ ...m, site: { ...m.site, home: { resource: 'authors' } } })) },
}

export const Dark: Story = { globals: { theme: 'dark' } }

export const RailCollapsed: Story = { parameters: { storage: { 'ra:rail': false }, viewportSize: { width: 1440, height: 600 } } }

export const Tablet: Story = { parameters: { viewportSize: { width: 900, height: 900 } } }

export const Mobile: Story = { parameters: { viewportSize: { width: 390, height: 844 } } }

export const MobileMenuOpen: Story = {
  parameters: { viewportSize: { width: 390, height: 844 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'Open menu' }))
    await expect(await screen.findByRole('tree', { name: 'Menu' })).toBeVisible()
  },
}

export const SignInRequired: Story = {
  parameters: {
    msw: { handlers: [http.get('/api/admin/_manifest', () => apiError(401, 'unauthorized', 'Sign in required'))] },
    viewportSize: { width: 1280, height: 720 },
  },
}

export const NotFound: Story = {
  parameters: { route: '/posts/5000/comments', viewportSize: { width: 1280, height: 640 } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByRole('heading', { name: 'Not found' })).toBeVisible()
    await expect(canvas.getByRole('link', { name: 'Back to home' })).toHaveAttribute('href', '/')
    await expect(await canvas.findByRole('tree', { name: 'Menu' })).toBeVisible()
  },
}

export const NotFoundDark: Story = { ...NotFound, globals: { theme: 'dark' } }

export const BrandWithLogo: Story = {
  parameters: { route: '/', ...manifest((m) => ({ ...m, site: { ...m.site, title_image: '/mocks/logo.svg' } })), viewportSize: { width: 1280, height: 480 } },
}

export const UtilityMenuOpen: Story = {
  parameters: { viewportSize: { width: 1280, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Dana Whitfield, account menu/ }))
    await expect(await screen.findByRole('menuitem', { name: 'Sign out' })).toBeVisible()
  },
}

export const UtilityMenuWithUiSwitch: Story = {
  parameters: { ...switchable, viewportSize: { width: 1280, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Dana Whitfield, account menu/ }))
    await expect(await screen.findByRole('menuitem', { name: 'Use classic admin' })).toBeVisible()
  },
}

export const UtilityMenuCollapsedRail: Story = {
  parameters: { storage: { 'ra:rail': false }, viewportSize: { width: 1280, height: 480 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Dana Whitfield, account menu/ }))
    await expect(await screen.findByRole('menuitem', { name: 'Admin docs' })).toBeVisible()
  },
}

export const UtilityMenuMobile: Story = {
  parameters: { viewportSize: { width: 390, height: 640 } },
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: /Dana Whitfield, account menu/ }))
    await expect(await screen.findByRole('menuitem', { name: 'Sign out' })).toBeVisible()
  },
}

// The last manifest paints the shell at once; the live one never arrives here.
export const PaintsFromPersistedManifest: Story = {
  parameters: {
    storage: { 'ra:manifest:user': 'u-1', 'ra:manifest:v2:u-1': manifestBody },
    msw: {
      handlers: [
        http.get('/api/admin/_manifest', async () => {
          await delay('infinite')
          return HttpResponse.json(manifestBody)
        }),
      ],
    },
  },
}

export const SchemaMismatch: Story = {
  parameters: { ...manifest((m) => ({ ...m, schema_version: 3 })), viewportSize: { width: 1280, height: 520 } },
}
