import { QueryClient } from '@tanstack/react-query'
import { retryDelay, retryQuery } from '@/api/retry'

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: retryQuery,
      retryDelay,
    },
  },
})
