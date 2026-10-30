import { useState } from 'react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ThemeProvider } from 'next-themes'
import { createMemoryRouter, RouterProvider } from 'react-router'
import { Toaster } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'

type ProvidersProps = {
  theme: string
  route?: string
  routePath?: string
  storage?: Record<string, unknown>
  children: React.ReactNode
}

// Persisted UI state (menu groups, rail) must not leak between stories.
function resetStorage(seed: Record<string, unknown> = {}) {
  Object.keys(localStorage)
    .filter((key) => key.startsWith('ra:'))
    .forEach((key) => localStorage.removeItem(key))
  Object.entries(seed).forEach(([key, value]) => localStorage.setItem(key, JSON.stringify(value)))
}

export function Providers({ theme, route = '/', routePath, storage, children }: ProvidersProps) {
  useState(() => resetStorage(storage))
  const [router] = useState(() => createMemoryRouter([{ path: routePath ?? '*', element: children }, { path: '*', element: <p className="p-4 text-sm text-muted-foreground">Navigated away from the story.</p> }], { initialEntries: [route] }))
  const [client] = useState(() => new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: Infinity } } }))
  return (
    <ThemeProvider attribute="class" forcedTheme={theme} enableSystem={false}>
      <QueryClientProvider client={client}>
        <TooltipProvider>
          <RouterProvider router={router} />
          <Toaster />
        </TooltipProvider>
      </QueryClientProvider>
    </ThemeProvider>
  )
}
