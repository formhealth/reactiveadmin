const UUID_SOURCE = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
const UUID = new RegExp(`^${UUID_SOURCE}$`, 'i')
const IDENTIFIER = /(^|[_\s])id$/i

export const UUID_IN_TEXT = new RegExp(`(${UUID_SOURCE})`, 'i')

export const isUuid = (value: unknown): value is string => typeof value === 'string' && UUID.test(value)

export const shortId = (uuid: string) => uuid.slice(0, 8)

// Matches `id`, `author_id`, `External ID`, `ref_id`, ...
export const isIdentifierName = (name?: string | null) => !!name && IDENTIFIER.test(name.trim())

// What an operator pastes to pick a record directly: a UUID or an integer primary key.
export const isIdLike = (value: string) => isUuid(value) || /^\d+$/.test(value)
