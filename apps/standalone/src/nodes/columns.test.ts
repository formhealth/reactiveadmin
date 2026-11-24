import { describe, expect, it } from 'vitest'
import type { Node as NodeData } from '@/api/generated/model'
import { columnLimits, columnsLayout } from './columns'

const column = (extra: Partial<NodeData> = {}): NodeData => ({ type: 'column', children: [], ...extra })

describe('columnsLayout', () => {
  it('shares the row equally by default', () => {
    expect(columnsLayout([column(), column()]).tracks).toBe('minmax(0, 1fr) minmax(0, 1fr)')
  })

  it('sizes each column by its span', () => {
    expect(columnsLayout([column({ span: 2 }), column()]).tracks).toBe('minmax(0, 2fr) minmax(0, 1fr)')
  })

  it('keeps a column at least its min width', () => {
    expect(columnsLayout([column({ min_width_css: '200px' }), column()]).tracks).toBe('minmax(200px, 1fr) minmax(0, 1fr)')
  })

  it('reads percentages as of the whole row', () => {
    expect(columnsLayout([column({ min_width_css: '30%' })]).tracks).toBe('minmax(30cqw, 1fr)')
    expect(columnLimits(column({ max_width_css: '50%', min_width_css: '10rem' }))).toEqual({
      style: { '--min': '10rem', '--max': '50cqw' },
      className: 'min-w-(--min) max-w-(--max)',
    })
    expect(columnLimits(column())).toEqual({})
  })

  it('goes side by side by container width, later with more columns', () => {
    expect([1, 2, 3, 4, 6].map((n) => columnsLayout(Array.from({ length: n }, () => column())).className)).toEqual([
      'grid-cols-(--tracks)',
      '@3xl:grid-cols-(--tracks)',
      '@5xl:grid-cols-(--tracks)',
      '@7xl:grid-cols-(--tracks)',
      '@7xl:grid-cols-(--tracks)',
    ])
  })
})
