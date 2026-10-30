import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '@/api/fetcher'
import { sendWithResend } from './resend'

const retry = (retryAfter?: number) => new ApiError(409, 'retry', 'busy', undefined, retryAfter)

describe('sendWithResend', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('sends again once after Retry-After and returns the second result', async () => {
    const send = vi.fn().mockRejectedValueOnce(retry(2)).mockResolvedValueOnce('saved')
    const onWait = vi.fn()
    const result = sendWithResend(send, true, onWait)

    await vi.advanceTimersByTimeAsync(1999)
    expect(send).toHaveBeenCalledTimes(1)
    expect(onWait).toHaveBeenCalledOnce()

    await vi.advanceTimersByTimeAsync(1)
    await expect(result).resolves.toBe('saved')
    expect(send).toHaveBeenCalledTimes(2)
  })

  it('waits a second when the server named no delay', async () => {
    const send = vi.fn().mockRejectedValueOnce(retry()).mockResolvedValueOnce('saved')
    const result = sendWithResend(send, true)
    await vi.advanceTimersByTimeAsync(1000)
    await expect(result).resolves.toBe('saved')
  })

  it('gives the second retry to the caller instead of looping', async () => {
    const send = vi.fn().mockRejectedValue(retry(1))
    const result = sendWithResend(send, true)
    const settled = expect(result).rejects.toMatchObject({ code: 'retry' })
    await vi.advanceTimersByTimeAsync(1000)
    await settled
    expect(send).toHaveBeenCalledTimes(2)
  })

  it('does not resend when told not to (creates)', async () => {
    const send = vi.fn().mockRejectedValue(retry(1))
    await expect(sendWithResend(send, false)).rejects.toMatchObject({ code: 'retry' })
    expect(send).toHaveBeenCalledTimes(1)
  })

  it('never resends a stale write', async () => {
    const send = vi.fn().mockRejectedValue(new ApiError(409, 'stale'))
    await expect(sendWithResend(send, true)).rejects.toMatchObject({ code: 'stale' })
    expect(send).toHaveBeenCalledTimes(1)
  })
})
