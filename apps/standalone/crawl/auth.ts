import { pathToFileURL } from 'node:url'
import type { BrowserContext } from 'playwright'

export type LoginContext = { baseUrl: string; context: BrowserContext; env: NodeJS.ProcessEnv }
// Leaves a signed-in session in `context` (cookies, or storage); typically `context.request.post(...)` or `context.addCookies(...)`.
export type LoginHook = (login: LoginContext) => void | Promise<void>

export const parseCookies = (header: string) =>
  header
    .split(';')
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const at = part.indexOf('=')
      if (at < 1) throw new Error('CRAWL_COOKIE must look like "name=value" or "a=1; b=2"')
      return { name: part.slice(0, at), value: part.slice(at + 1) }
    })

export async function signIn(login: LoginContext, hookPath?: string) {
  const { baseUrl, context, env } = login
  if (env.CRAWL_COOKIE) await context.addCookies(parseCookies(env.CRAWL_COOKIE).map((cookie) => ({ ...cookie, url: baseUrl })))
  if (hookPath) {
    const hook = ((await import(pathToFileURL(hookPath).href)) as { default?: LoginHook }).default
    if (typeof hook !== 'function') throw new Error(`${hookPath} must default-export a function`)
    await hook(login)
  }
}
