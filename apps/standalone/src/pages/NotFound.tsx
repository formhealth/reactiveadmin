import { ApiError } from '@/api/fetcher'
import { ErrorState } from '@/components/ErrorState'
import { useDocumentTitle } from '@/hooks/useManifest'

// Served by a Rails host, Layout sends an address the client has no route for to the classic admin, which may have it.
export function NotFound() {
  useDocumentTitle('Not found')
  return <ErrorState error={new ApiError(404)} backTo={{ to: '/', label: 'Back to home' }} />
}
