import type { Decorator, Preview } from '@storybook/react-vite'
import { type SetupWorker, setupWorker } from 'msw/browser'
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

// Kept on globalThis so a re-evaluated preview (HMR, a second story file in the same page) reuses the running worker
// instead of starting another one that races it for requests.
const shared = globalThis as { raMswWorker?: Promise<SetupWorker>; raLazyModules?: Promise<unknown> }
const startWorker = () =>
  (shared.raMswWorker ??= (async () => {
    const worker = setupWorker(...handlers)
    await worker.start({ quiet: true, onUnhandledRequest: 'bypass' })
    return worker
  })())

// The app's code-split modules, loaded before a story renders. Otherwise the first story of each file loads them in a
// waterfall (route, then page, then node chunks, each after the request before it) inside its play's `findBy` window,
// which a busy CI runner, with other story files rendering in parallel, overruns.
const lazyModules = () =>
  (shared.raLazyModules ??= Promise.all([
    import('@/pages/ActionPage'),
    import('@/pages/GroupOverview'),
    import('@/pages/PageView'),
    import('@/pages/ResourceForm'),
    import('@/pages/ResourceIndex'),
    import('@/pages/ResourceOrPage'),
    import('@/pages/ResourceShow'),
    import('@/views/ActionView'),
    import('@/forms/FormDialog'),
    import('@/nodes/InlineForm'),
    import('@/nodes/rich'),
    import('@/nodes/frames'),
    import('@/nodes/media'),
    import('@/json/JsonView'),
    import('@/json/JsonDiff'),
    import('@/json/JsonEditor'),
    import('@/components/filters/DateRangeCalendar'),
    import('@/components/menu/CommandPalette'),
    import('@/components/menu/MobileMenu'),
  ]))

const preview: Preview = {
  decorators: [withProviders],
  loaders: [mswLoader(startWorker), lazyModules],
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
