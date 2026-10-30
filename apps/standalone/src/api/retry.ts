import { ApiError } from './fetcher'

// Longer than this and a retry would just look like a hang; the toast has already told the operator.
const MAX_RETRY_AFTER = 30

export const retryQuery = (count: number, error: unknown) => {
  if (!(error instanceof ApiError)) return count < 2
  if (error.status === 429) return count < 1 && (error.retryAfter ?? 1) <= MAX_RETRY_AFTER
  return error.status >= 500 && count < 2
}

export const retryDelay = (attempt: number, error: unknown) =>
  error instanceof ApiError && error.status === 429 ? (error.retryAfter ?? 1) * 1000 : Math.min(1000 * 2 ** attempt, 30_000)
