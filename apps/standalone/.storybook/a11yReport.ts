import { appendFileSync } from 'node:fs'
import type { BrowserCommand } from 'vitest/node'

// Appends violations as JSONL to $A11Y_REPORT (when set) for before/after tallies.
export const a11yReport: BrowserCommand<[string]> = (_ctx, line) => {
  if (process.env.A11Y_REPORT) appendFileSync(process.env.A11Y_REPORT, `${line}\n`)
}
