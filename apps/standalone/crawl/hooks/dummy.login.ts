import type { LoginHook } from '../auth.ts'

// Signs in to the gem's dummy app through its test-only session endpoint. Set by scripts/crawl-dummy.mjs.
const login: LoginHook = async ({ context, env }) => {
  const origin = env.CRAWL_DUMMY_ORIGIN
  if (!origin) throw new Error('CRAWL_DUMMY_ORIGIN is not set; run this hook through `pnpm crawl:dummy`')
  const response = await context.request.post(`${origin}/test/sign_in`, { form: { id: env.CRAWL_DUMMY_ADMIN_ID ?? '1' } })
  if (!response.ok()) throw new Error(`dummy sign-in answered ${response.status()}`)
}

export default login
