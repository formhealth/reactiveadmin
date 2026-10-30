import { toast } from 'sonner'
import { ApiError, errorMessage } from '@/api/fetcher'
import type { ResourceSummary } from '@/api/generated/model'

// The server refuses what an `api` guard denies (403 `api_denied`); the answer says where to go instead.
export const isApiDenied = (error: unknown): error is ApiError => error instanceof ApiError && error.status === 403 && error.code === 'api_denied'

export function toastError(error: unknown) {
  const url = isApiDenied(error) ? error.body?.classic_url : undefined
  toast.error(errorMessage(error), url ? { action: { label: 'Open in classic admin', onClick: () => void window.open(url, '_blank', 'noopener,noreferrer') } } : undefined)
}

// Where a page of the resource that the API refuses lives in the classic admin; undefined when it isn't reserved.
export function classicPage(summary: ResourceSummary | undefined, action: string, path = '') {
  const reserved = summary?.api_denied
  return reserved?.actions?.includes(action) && reserved.classic_url ? `${reserved.classic_url}${path}` : undefined
}

export const isDenied = (summary: ResourceSummary | undefined, action: string) => !!summary?.api_denied?.actions?.includes(action)
