import type { ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useLocation } from 'react-router'
import { invalidateData } from '@/lib/records'
import { ErrorBoundary } from './ErrorBoundary'
import { ErrorPage } from './fallbacks'
import { classicHere, classicHereNow } from './urls'

export function RouteBoundary({ children }: { children: ReactNode }) {
  const { pathname } = useLocation()
  const queryClient = useQueryClient()
  return (
    <ErrorBoundary
      where="route"
      resetKey={pathname}
      fallback={(reset) => (
        <ErrorPage
          href={classicHere(pathname)}
          onRetry={() => {
            invalidateData(queryClient)
            reset()
          }}
        />
      )}
    >
      {children}
    </ErrorBoundary>
  )
}

// Last resort above the router and providers, so it reads nothing from app state but the location.
export function AppBoundary({ children }: { children: ReactNode }) {
  return (
    <ErrorBoundary where="app" fallback={(reset) => <ErrorPage href={classicHereNow()} onRetry={reset} />}>
      {children}
    </ErrorBoundary>
  )
}
