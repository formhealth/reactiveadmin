// @vitest-environment jsdom
import { createBrowserRouter } from 'react-router'
import { describe, expect, it } from 'vitest'
import { isLanding, trackLanding } from './landing'

const boot = (historyState?: unknown) => {
  window.history.replaceState(historyState, '', '/admin/posts')
  const router = createBrowserRouter([{ path: '*', element: null }])
  trackLanding(router)
  return router
}

describe('isLanding', () => {
  it('is the first page of a load', () => {
    const router = boot()

    expect(isLanding(router.state.location.key)).toBe(true)
    router.dispose()
  })

  it('still is after a reload, when the browser restores the key of the history entry', () => {
    const router = boot({ usr: null, key: 'k7q2m9', idx: 3 })

    expect(router.state.location.key).toBe('k7q2m9')
    expect(isLanding('k7q2m9')).toBe(true)
    expect(isLanding('default')).toBe(false)
    router.dispose()
  })

  it('is not a page reached by navigating inside the app', async () => {
    const router = boot({ usr: null, key: 'k7q2m9', idx: 3 })

    await router.navigate('/admin/posts/1')
    expect(isLanding(router.state.location.key)).toBe(false)
    await router.navigate('/admin/posts')
    expect(isLanding(router.state.location.key)).toBe(false)
    router.dispose()
  })
})
