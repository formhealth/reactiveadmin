import { sameOrigin } from './classic'

// An image or document URL the browser may load directly: http(s) only, on this site or a host the server trusts.
// Markup can name any URL, so the node's `src` is checked again here; `data:`, `javascript:`, protocol-relative and
// credentialed URLs never pass, and neither does anything on another host (sensitive data must not leak to third parties).
const WEB_URL = /^(?:https?:\/\/|\/(?!\/))/i
// Printable ASCII only, so no whitespace, control characters or backslash tricks.
const UNSAFE_CHARS = /[^\x21-\x7e]|\\/

export function safeMediaSrc(src: string | null | undefined, trustedHosts: readonly string[] = [], from = globalThis.location?.href) {
  if (!src || UNSAFE_CHARS.test(src) || !WEB_URL.test(src)) return undefined
  try {
    const url = new URL(src, from)
    if (url.username || url.password) return undefined
    return sameOrigin(src, from) || trustedHosts.some((host) => host.toLowerCase() === url.hostname) ? src : undefined
  } catch {
    return undefined
  }
}
