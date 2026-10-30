import { mkdtempSync, readdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { PNG } from 'pngjs'
import { describe, expect, it } from 'vitest'
import { compareBaseline } from './baselines.ts'

const png = (width: number, height: number, paint: (x: number, y: number) => number) => {
  const image = new PNG({ width, height })
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) image.data.writeUInt32BE(paint(x, y), (y * width + x) * 4)
  return PNG.sync.write(image)
}
const white = () => 0xffffffff
const settings = () => ({ baselineDir: mkdtempSync(path.join(tmpdir(), 'base-')), outDir: mkdtempSync(path.join(tmpdir(), 'out-')), update: false, threshold: 0.001 })

describe('compareBaseline', () => {
  it('creates a missing baseline, then matches it', () => {
    const s = settings()
    expect(compareBaseline('index:posts', png(10, 10, white), s).outcome).toBe('created')
    expect(compareBaseline('index:posts', png(10, 10, white), s).outcome).toBe('match')
    expect(readdirSync(s.baselineDir)).toEqual(['index_posts.png'])
  })

  it('writes a diff image when pixels change beyond the threshold', () => {
    const s = settings()
    compareBaseline('x', png(10, 10, white), s)
    expect(compareBaseline('x', png(10, 10, (x) => (x < 5 ? 0x000000ff : 0xffffffff)), s).outcome).toBe('diff')
    expect(readdirSync(path.join(s.outDir, 'diffs'))).toEqual(['x.png'])
  })

  it('reports a size change, and overwrites when updating', () => {
    const s = settings()
    compareBaseline('x', png(10, 10, white), s)
    expect(compareBaseline('x', png(10, 12, white), s)).toMatchObject({ outcome: 'diff', message: expect.stringContaining('size changed') })
    expect(compareBaseline('x', png(10, 12, white), { ...s, update: true }).outcome).toBe('updated')
    expect(compareBaseline('x', png(10, 12, white), s).outcome).toBe('match')
  })
})
