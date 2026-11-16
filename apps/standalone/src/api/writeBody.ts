const isBlob = (value: unknown): value is Blob => value instanceof Blob

const hasBlob = (value: unknown): boolean => isBlob(value) || (typeof value === 'object' && value !== null && Object.values(value).some(hasBlob))

// Rails' multipart names: `author[avatar]`, `author[tag_ids][]`. Null goes out blank, as a browser form sends it.
const fields = (key: string, value: unknown): [string, string | Blob][] =>
  value === undefined
    ? []
    : isBlob(value)
      ? [[key, value]]
      : Array.isArray(value)
        ? // An emptied list (`tag_ids: []`) is a clear, sent as Rails' blank entry; nested rows have nothing to send.
          value.length === 0 && !key.endsWith('_attributes]')
          ? [[`${key}[]`, '']]
          : value.flatMap((v) => fields(`${key}[]`, v))
        : value !== null && typeof value === 'object'
          ? Object.entries(value).flatMap(([k, v]) => fields(key ? `${key}[${k}]` : k, v))
          : [[key, value === null ? '' : String(value)]]

// Orval's form-data hook for write bodies with a file control. Like `saveRecord`, it sends JSON unless a file is
// present; the Blob's type becomes the request's Content-Type, since the generated call sets no header.
export const writeBody = <Body>(body: Body): FormData | Blob => {
  if (!hasBlob(body)) return new Blob([JSON.stringify(body)], { type: 'application/json' })
  const data = new FormData()
  for (const [name, value] of fields('', body)) data.append(name, value)
  return data
}
