export type UiChoice = 'new' | 'classic'

const NAME = 'reactiveadmin_ui'
const YEAR = 31_536_000

// The choice lives in a plain cookie that the server's shell middleware reads (browsers can't add a header to a
// navigation). It holds a preference and nothing else, so the client and the classic dashboard both write it, from the
// root path, which covers the admin wherever it is mounted.
export function readUiChoice(cookies = document.cookie): UiChoice | undefined {
  const value = cookies.split('; ').find((pair) => pair.startsWith(`${NAME}=`))?.slice(NAME.length + 1)
  return value === 'new' || value === 'classic' ? value : undefined
}

export function storeUiChoice(choice: UiChoice | undefined, jar: { cookie: string } = document, secure = globalThis.location?.protocol === 'https:') {
  jar.cookie = [`${NAME}=${choice ?? ''}`, 'path=/', 'SameSite=Lax', `max-age=${choice ? YEAR : 0}`, ...(secure ? ['Secure'] : [])].join('; ')
}

// `classic=1` is the one-off escape hatch: once the user chose, it shouldn't hold them in classic.
export function withoutClassic(href: string) {
  const url = new URL(href)
  url.searchParams.delete('classic')
  return url.href
}

// Stores the choice, then loads the same page again: the other UI is a different document at the same URL. A page only
// the client has needs `destination`, its counterpart in the other UI.
export function switchUi(choice: UiChoice, here: Pick<Location, 'href' | 'assign'> = location, jar: { cookie: string } = document, destination?: string) {
  storeUiChoice(choice, jar)
  // With cookies blocked a reload would only repeat this.
  if (readUiChoice(jar.cookie) !== choice) return
  here.assign(destination ?? withoutClassic(here.href))
}

// A host's `ui.default` of `new` takes effect where there is no choice yet, unless this load asked for classic.
export const appliesDefault = (mode: string | undefined, cookies = document.cookie, search = location.search) =>
  mode === 'new' && readUiChoice(cookies) === undefined && new URLSearchParams(search).get('classic') !== '1'
