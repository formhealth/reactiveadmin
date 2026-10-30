export type ClientError = { where: string; kind: string; message: string }

// Only names and kinds go in. Props, record data and error text can carry sensitive data, so callers pass `error.name`, never `error.message`.
export function reportClientError(error: ClientError) {
  if (import.meta.env.DEV) console.error('[client-error]', error)
}
