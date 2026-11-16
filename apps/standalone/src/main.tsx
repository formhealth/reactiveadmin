import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { boundedSession, leaveIfUnavailable } from './lib/boot'
import { verifyCachedManifest } from './lib/manifestCache'

async function enableMocks() {
  if (import.meta.env.VITE_MOCKS !== '1') return
  const { worker } = await import('./mocks/browser')
  // BASE_URL keeps the worker's URL and scope under the demo's subpath.
  await worker.start({ onUnhandledFrame: 'bypass', quiet: true, serviceWorker: { url: `${import.meta.env.BASE_URL}mockServiceWorker.js` } })
}

const session = boundedSession()

enableMocks()
  .then(() => verifyCachedManifest(session))
  .then(() => leaveIfUnavailable(session))
  .then((leaving) => {
    if (!leaving)
      createRoot(document.getElementById('root')!).render(
        <StrictMode>
          <App />
        </StrictMode>,
      )
  })
