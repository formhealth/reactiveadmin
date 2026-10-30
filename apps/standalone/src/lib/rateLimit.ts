import { toast } from 'sonner'

export const rateLimitMessage = (seconds?: number) => `You're doing that too fast — try again in ${seconds ? `${seconds}s` : 'a moment'}`

// One toast at a time: a burst of rejected requests replaces it rather than stacking.
export const toastRateLimited = (seconds?: number) =>
  toast.warning(rateLimitMessage(seconds), { id: 'rate-limited', duration: Math.min(Math.max((seconds ?? 5) * 1000, 4000), 15000) })
