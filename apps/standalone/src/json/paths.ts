export type PathKey = string | number

const IDENTIFIER = /^[A-Za-z_$][\w$]*$/

// `a.b[0].c`; keys that aren't identifiers (dots, spaces, leading digits) fall back to `["key"]`.
export const pathString = (path: PathKey[]) =>
  path.reduce<string>((out, key) => {
    if (typeof key === 'number') return `${out}[${key}]`
    if (!IDENTIFIER.test(key)) return `${out}[${JSON.stringify(key)}]`
    return out ? `${out}.${key}` : key
  }, '')
