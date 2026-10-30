import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { boundedSession, leaveIfUnavailable } from './lib/boot'
import { verifyCachedManifest } from './lib/manifestCache'

async function enableMocks() {
  if (import.meta.env.VITE_MOCKS !== '1') return
  const { worker } = await import('./mocks/browser')
  await worker.start({ onUnhandledFrame: 'bypass', quiet: true })
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
