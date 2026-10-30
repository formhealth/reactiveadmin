import { isRetry } from '@/api/fetcher'

// Sends once more after the server's `Retry-After` when it answers `retry`; a second `retry` is the caller's to surface.
export async function sendWithResend<T>(send: () => Promise<T>, resend: boolean, onWait?: () => void): Promise<T> {
  try {
    return await send()
  } catch (error) {
    if (!resend || !isRetry(error)) throw error
    onWait?.()
    await new Promise((resolve) => setTimeout(resolve, (error.retryAfter ?? 1) * 1000))
    return send()
  }
}
