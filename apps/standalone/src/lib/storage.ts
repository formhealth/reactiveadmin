export const STORAGE_PREFIX = 'ra:'

// Everything the client persists is under one prefix, so a sign-out, a 401 or a different user drops it in one go.
export function clearClientStorage() {
  try {
    Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i) ?? '')
      .filter((key) => key.startsWith(STORAGE_PREFIX))
      .forEach((key) => localStorage.removeItem(key))
  } catch {
    // storage unavailable
  }
}
