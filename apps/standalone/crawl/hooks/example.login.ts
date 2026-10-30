import type { LoginHook } from '../auth.ts'

// Copy to apps/standalone/crawl.login.ts (git-ignored) and adapt. The hook runs once, before the manifest is
// fetched, and must leave a signed-in session in `context`: cookies, or a request that sets them.
const login: LoginHook = async ({ baseUrl, context, env }) => {
  const cookie = env.MY_APP_SESSION
  if (!cookie) throw new Error('set MY_APP_SESSION to a dev session cookie value')
  await context.addCookies([{ name: '_myapp_session', value: cookie, url: baseUrl }])
}

export default login
