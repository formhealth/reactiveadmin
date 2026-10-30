import { QueryClientProvider } from '@tanstack/react-query'
import { ThemeProvider } from 'next-themes'
import { createBrowserRouter, RouterProvider } from 'react-router'
import { Toaster } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'
import { queryClient } from '@/api/queryClient'
import { AppBoundary } from '@/boundaries/RouteBoundary'
import { routerBase } from '@/lib/base'
import { trackLanding } from '@/lib/landing'
import { routes } from '@/routes'

const router = createBrowserRouter(routes, { basename: routerBase || undefined })
trackLanding(router)

export default function App() {
  return (
    <AppBoundary>
      <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
        <QueryClientProvider client={queryClient}>
          <TooltipProvider>
            <RouterProvider router={router} />
            <Toaster />
          </TooltipProvider>
        </QueryClientProvider>
      </ThemeProvider>
    </AppBoundary>
  )
}
