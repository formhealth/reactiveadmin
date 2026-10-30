import type { Decorator, Preview } from '@storybook/react-vite'
import { setupWorker } from 'msw/browser'
import { mswLoader } from 'msw-storybook-addon/csf3'
import { handlers } from '@/mocks/handlers'
import '../src/index.css'
import { Providers } from './Providers'

declare module 'storybook/internal/csf' {
  interface Parameters {
    /** Initial URL for the story's MemoryRouter. */
    route?: string
    /** Route pattern to render the story under, for components that read URL params. */
    routePath?: string
    /** localStorage entries (`ra:*`) seeded before the story renders. */
    storage?: Record<string, unknown>
  }
}

const withProviders: Decorator = (Story, { id, globals, parameters }) => (
  <Providers key={`${id}-${globals.theme}`} theme={globals.theme} route={parameters.route} routePath={parameters.routePath} storage={parameters.storage}>
    <Story />
  </Providers>
)

const preview: Preview = {
  decorators: [withProviders],
  loaders: [
    mswLoader(async () => {
      const worker = setupWorker(...handlers)
      await worker.start({ quiet: true, onUnhandledRequest: 'bypass' })
      return worker
    }),
  ],
  globalTypes: {
    theme: {
      description: 'Color theme',
      toolbar: {
        icon: 'circlehollow',
        dynamicTitle: true,
        items: [
          { value: 'light', title: 'Light' },
          { value: 'dark', title: 'Dark' },
        ],
      },
    },
  },
  initialGlobals: { theme: import.meta.env.VITE_A11Y_THEME ?? 'light' },
  parameters: {
    layout: 'padded',
    controls: { disable: true },
    viewportSize: { width: 1280, height: 800 },
  },
}

export default preview
