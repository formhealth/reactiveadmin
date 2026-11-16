import type { Browser, BrowserContext } from 'playwright'

export type ParityStatus = 'match' | 'mismatch' | 'unsupported'
// Ids and counts only: comparing or recording cell values would put record data in the report.
export type Parity = {
  resource: string
  status: ParityStatus
  classicCount?: number
  reactCount?: number
  onlyClassic: string[]
  onlyReact: string[]
  reason?: string
}

const MAX_LISTED = 10

// Compares first pages as sets of ids: both UIs sort by the same default, but ties may come back in either order.
export function compareRows(resource: string, classic: string[] | undefined, react: string[] | undefined): Parity {
  const unsupported = (reason: string): Parity => ({ resource, status: 'unsupported', classicCount: classic?.length, reactCount: react?.length, onlyClassic: [], onlyReact: [], reason })
  if (!react) return unsupported('the React index did not render record ids')
  if (!classic) return unsupported('the classic index has no table of records this can read')
  const inReact = new Set(react)
  const inClassic = new Set(classic)
  const onlyClassic = [...inClassic].filter((id) => !inReact.has(id))
  const onlyReact = [...inReact].filter((id) => !inClassic.has(id))
  const same = classic.length === react.length && !onlyClassic.length && !onlyReact.length
  return {
    resource,
    status: same ? 'match' : 'mismatch',
    classicCount: classic.length,
    reactCount: react.length,
    onlyClassic: onlyClassic.slice(0, MAX_LISTED),
    onlyReact: onlyReact.slice(0, MAX_LISTED),
  }
}

// In the React page: every record on screen carries its id in `data-row-id` (table rows, cards, grid and blog items), and the
// index root reports its row count in `data-row-count`. Without that count (an older host build, or a page still loading) an
// empty list could be an index with no records or one that doesn't render ids, so it is undefined rather than [].
export const reactRowIds = () => {
  const count = document.querySelector<HTMLElement>('main [data-row-count]')?.dataset.rowCount
  const ids = [...document.querySelectorAll<HTMLElement>('main [data-row-id]')].map((el) => el.dataset.rowId!)
  return count === undefined || Number(count) !== ids.length ? undefined : ids
}

// In the classic page: a row's id is read from its own links (`{base}12`, `{base}12/edit`), which carry the same `to_param` the
// React rows use. Checkbox values are primary keys, so they only pick the own link among several (an association
// can link to another record of the same resource). Anything not positively identified is undefined, so the resource is
// reported as unsupported instead of compared on a guess; it is also undefined for a page this can't read, as opposed to an
// empty index.
export const classicRowIds = (base: string) => {
  const collection = document.querySelector('#main_content .paginated_collection')
  if (!collection) return document.querySelector('#main_content .blank_slate_container') ? [] : undefined
  const rows = [...collection.querySelectorAll<HTMLElement>('table.index_table tbody tr')]
  if (!rows.length) return undefined
  const idsOf = (links: HTMLAnchorElement[]) => [
    ...new Set(links.map((a) => new URL(a.href).pathname).filter((path) => path.startsWith(base)).map((path) => decodeURIComponent(path.slice(base.length).split('/')[0]))),
  ]
  const ids = rows.map((row) => {
    const member = idsOf([...row.querySelectorAll<HTMLAnchorElement>('a.member_link')])
    if (member.length) return member.length === 1 ? member[0] : undefined
    // A row's dom id can't be split into model prefix and key (`category_eu_widget`), so only the checkbox confirms a key.
    const pk = row.querySelector<HTMLInputElement>('input.collection_selection')?.value
    if (pk === undefined) return undefined
    const own = idsOf([...row.querySelectorAll<HTMLAnchorElement>('a[href]')]).filter((id) => id === pk)
    return own.length === 1 ? own[0] : undefined
  })
  return ids.every((id) => id !== undefined) ? (ids as string[]) : undefined
}

// A redirect (to sign-in, SSO or another resource's index) must not be read as this resource's records.
export const isIndexUrl = (url: string, origin: string, path: string) => {
  const target = new URL(url)
  const expected = new URL(path, origin)
  const trim = (p: string) => decodeURIComponent(p).replace(/\/$/, '')
  return target.origin === expected.origin && trim(target.pathname) === trim(expected.pathname)
}

export type ClassicLoad = {
  browser: Browser
  storageState: Awaited<ReturnType<BrowserContext['storageState']>>
  origin: string
  classicPath: string
  resource: string
  timeoutMs: number
}

// `classic=1` is the server's per-request escape hatch: it keeps a person who chose the new admin on the classic page.
export async function loadClassicIds({ browser, storageState, origin, classicPath, resource, timeoutMs }: ClassicLoad) {
  const base = `${classicPath}/${encodeURIComponent(resource)}/`
  const context = await browser.newContext({ storageState, locale: 'en-US', timezoneId: 'UTC' })
  try {
    const page = await context.newPage()
    const indexPath = base.slice(0, -1)
    await page.goto(`${origin}${indexPath}?classic=1`, { waitUntil: 'domcontentloaded', timeout: timeoutMs })
    if (!isIndexUrl(page.url(), origin, indexPath)) return undefined
    await page.waitForSelector('#main_content .paginated_collection, #main_content .blank_slate_container', { timeout: timeoutMs }).catch(() => {})
    return await page.evaluate(classicRowIds, base)
  } catch {
    return undefined
  } finally {
    await context.close()
  }
}
