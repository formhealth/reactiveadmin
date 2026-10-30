import { setProjectAnnotations } from '@storybook/react-vite'
import axe from 'axe-core'
import { toast } from 'sonner'
import type { AfterEach, BeforeEach } from 'storybook/internal/types'
import { commands, page } from 'vitest/browser'
import { AXE_TAGS as TAGS, BLOCKING_IMPACTS as BLOCKING, FRAGMENT_RULES, MODAL_SIBLINGS } from './a11yConfig'
import * as projectAnnotations from './preview'

const THEME = import.meta.env.VITE_A11Y_THEME ?? 'light'
const DISABLED_RULES = Object.fromEntries(FRAGMENT_RULES.map((id) => [id, { enabled: false }]))

// Resolves once the DOM has been quiet for `quietMs`, so data-driven stories finish rendering.
const settle = (quietMs = 200, maxMs = 4000) =>
  new Promise<void>((resolve) => {
    let timer = setTimeout(done, quietMs)
    const cap = setTimeout(done, maxMs)
    const observer = new MutationObserver(() => {
      clearTimeout(timer)
      timer = setTimeout(done, quietMs)
    })
    observer.observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true })
    function done() {
      observer.disconnect()
      clearTimeout(timer)
      clearTimeout(cap)
      resolve()
    }
  })

// Responsive stories declare their size in `parameters.viewportSize`; match it so layout-dependent plays find their controls.
const viewport: BeforeEach = async ({ parameters }) => {
  const { width, height } = parameters.viewportSize
  await page.viewport(width, height)
}

// Entrance animations start transparent, which fails `toBeVisible` in plays.
document.head.insertAdjacentHTML('beforeend', '<style>*,*::before,*::after{animation:none!important;transition:none!important}</style>')

// Sonner's toast store outlives a story: a leftover identical toast stacks behind the new one at opacity 0, failing
// `findAllByText(...)[0]` `toBeVisible` checks (and retries) and being audited by the next story.
const clearToasts = async () => {
  toast.dismiss()
  for (let i = 0; i < 20 && document.querySelector('[data-sonner-toast]'); i++) await new Promise((resolve) => setTimeout(resolve, 50))
}

const audit: AfterEach = async ({ id, parameters }) => {
  const { disable, config, options } = parameters.a11y ?? {}
  if (disable) return
  await settle()
  axe.reset()
  axe.configure({ ...config, rules: [...MODAL_SIBLINGS, ...(config?.rules ?? [])] })
  const { violations } = await axe.run(
    { include: document.body, exclude: ['.sb-wrapper', '#storybook-docs', '#storybook-highlights-root'] },
    { runOnly: { type: 'tag', values: TAGS }, ...options, rules: { ...DISABLED_RULES, ...options?.rules } },
  )
  const failures: string[] = []
  for (const { id: rule, impact, nodes } of violations) {
    const targets = nodes.map((n) => n.target.join(' '))
    const html = nodes.map((n) => n.html.slice(0, 220))
    const why = nodes.map((n) => (n.any[0] ?? n.all[0] ?? n.none[0])?.message)
    await commands.a11yReport(JSON.stringify({ story: id, theme: THEME, rule, impact, targets, html, why }))
    if (BLOCKING.includes(impact ?? '')) failures.push(`${rule} (${impact}): ${targets.join(' | ')}`)
  }
  if (failures.length) throw new Error(`a11y violations (${THEME} theme):\n${failures.join('\n')}`)
}

const a11y: AfterEach = async (context) => {
  try {
    await audit(context)
  } finally {
    await clearToasts()
  }
}

setProjectAnnotations([projectAnnotations, { beforeEach: viewport, afterEach: a11y }])
