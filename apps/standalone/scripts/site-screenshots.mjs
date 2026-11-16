// Captures the site's screenshots from the built demo. Serve it first: `pnpm --filter site build:full && pnpm --filter site preview`.
import { chromium } from 'playwright'

const base = process.argv[2] ?? 'http://localhost:4173/reactiveadmin/demo/'
const out = new URL('../../site/public/screenshots/', import.meta.url)
const shots = [
  { name: 'index', path: 'posts', viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 },
  { name: 'index-mobile', path: 'posts', viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true },
  { name: 'show-mobile', path: 'posts/5000', viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true },
]

const browser = await chromium.launch()
for (const scheme of ['light', 'dark']) {
  for (const { name, path, ...device } of shots) {
    const page = await browser.newPage({ ...device, colorScheme: scheme })
    await page.goto(new URL(path, base).href)
    await page.waitForLoadState('networkidle')
    // The demo banner is for visitors of the demo, not part of the product.
    await page.addStyleTag({ content: '[role="note"] { display: none !important }' })
    await page.waitForTimeout(500)
    await page.screenshot({ path: new URL(`${name}-${scheme}.png`, out).pathname })
    await page.close()
  }
}
await browser.close()
