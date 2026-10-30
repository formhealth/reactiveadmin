import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import pixelmatch from 'pixelmatch'
import { PNG } from 'pngjs'

// Rows and times change between runs, so baselines compare layout rather than data.
export const DEFAULT_MASKS = ['time', '[datetime]', '[data-crawl-mask]', '[data-sonner-toast]', 'main tbody']

export type BaselineOutcome = 'created' | 'updated' | 'match' | 'diff'
export type Comparison = { outcome: BaselineOutcome; message?: string }

const slug = (id: string) => id.replace(/[^\w.-]+/g, '_')

export function compareBaseline(
  id: string,
  shot: Buffer,
  { baselineDir, outDir, update, threshold }: { baselineDir: string; outDir: string; update: boolean; threshold: number },
): Comparison {
  const file = path.join(baselineDir, `${slug(id)}.png`)
  let baseline: Buffer | undefined
  try {
    baseline = readFileSync(file)
  } catch {}
  const save = () => {
    mkdirSync(baselineDir, { recursive: true })
    writeFileSync(file, shot)
  }
  if (!baseline) return save(), { outcome: 'created' }
  if (update) return save(), { outcome: 'updated' }

  const before = PNG.sync.read(baseline)
  const after = PNG.sync.read(shot)
  if (before.width !== after.width || before.height !== after.height)
    return { outcome: 'diff', message: `size changed from ${before.width}x${before.height} to ${after.width}x${after.height}` }

  const diff = new PNG({ width: after.width, height: after.height })
  const changed = pixelmatch(before.data, after.data, diff.data, after.width, after.height, { threshold: 0.1 })
  const ratio = changed / (after.width * after.height)
  if (ratio <= threshold) return { outcome: 'match' }

  mkdirSync(path.join(outDir, 'diffs'), { recursive: true })
  writeFileSync(path.join(outDir, 'diffs', `${slug(id)}.png`), PNG.sync.write(diff))
  return { outcome: 'diff', message: `${(ratio * 100).toFixed(2)}% of pixels changed (limit ${(threshold * 100).toFixed(2)}%)` }
}
