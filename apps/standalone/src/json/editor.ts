export type Parsed = { ok: true; value: unknown } | { ok: false; error: string }

export const blank = (text: string) => text.trim() === ''

// Blank text is a null value, matching how the form submits an untouched json field.
export function parseText(text: string): Parsed {
  if (blank(text)) return { ok: true, value: null }
  try {
    return { ok: true, value: JSON.parse(text) }
  } catch (e) {
    return { ok: false, error: describeError(text, e) }
  }
}

export const toText = (value: unknown) => JSON.stringify(value, null, 2)

export const formatText = (text: string) => {
  const parsed = parseText(text)
  return parsed.ok && !blank(text) ? toText(parsed.value) : text
}

const INCOMPLETE = /end of JSON input|unterminated|unexpected end/i
const POSITION = /position (\d+)/
const MAX_LOCATE = 200_000

// Failing on something other than running out of input (some engines word that as a position at the very end).
const fails = (text: string) => {
  try {
    JSON.parse(text)
    return false
  } catch (e) {
    const { message } = e as Error
    const at = POSITION.exec(message)?.[1]
    return !INCOMPLETE.test(message) && !(at !== undefined && Number(at) >= text.length)
  }
}

// Modern engines name the bad token but not where it is. A valid-so-far prefix only ever fails as "incomplete",
// so the shortest prefix that fails any other way ends on the offending character.
function errorIndex(text: string, message: string) {
  const reported = POSITION.exec(message)?.[1]
  if (reported) return Number(reported)
  if (text.length > MAX_LOCATE) return undefined
  if (!fails(text)) return text.length
  let [low, high] = [1, text.length]
  while (low < high) {
    const mid = (low + high) >> 1
    if (fails(text.slice(0, mid))) high = mid
    else low = mid + 1
  }
  return low - 1
}

export function describeError(text: string, error: unknown) {
  // The engine echoes the document after the token; only the token is useful here.
  const message = (error instanceof Error ? error.message : 'Invalid JSON').replace(/,\s*(?:\.\.\.)?".*"\s*is not valid JSON$/s, '').replace(/ in JSON at position \d+.*$/s, '')
  const index = errorIndex(text, error instanceof Error ? error.message : '')
  if (index === undefined) return message
  const lines = text.slice(0, index).split('\n')
  return `${message} (line ${lines.length}, column ${lines.at(-1)!.length + 1})`
}
