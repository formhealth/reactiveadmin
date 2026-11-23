import type { CSSProperties } from 'react'
import type { Node as NodeData } from '@/api/generated/model'

// Columns go side by side by the width of the box they sit in, not the viewport (the nav rail takes 18rem of it):
// two from 48rem, three from 64rem, more from 80rem, so none is narrower than about 20rem.
const SIDE_BY_SIDE = ['grid-cols-(--tracks)', 'grid-cols-(--tracks)', '@3xl:grid-cols-(--tracks)', '@5xl:grid-cols-(--tracks)', '@7xl:grid-cols-(--tracks)']

// AA's percentages are of the whole row; inside a column's grid area they'd be of its share.
const ofRow = (length: string) => length.replace(/%$/, 'cqw')

// Each column's share of the row is its `span` (AA's `column span:`), and never less than its min width.
export function columnsLayout(columns: NodeData[]): { tracks: string; className: string } {
  return {
    tracks: columns.map((column) => `minmax(${column.min_width_css ? ofRow(column.min_width_css) : 0}, ${column.span ?? 1}fr)`).join(' '),
    className: SIDE_BY_SIDE[Math.min(columns.length, SIDE_BY_SIDE.length - 1)],
  }
}

// On the column itself, so the limits hold when the columns stack too.
export function columnLimits({ min_width_css: min, max_width_css: max }: NodeData): { style?: CSSProperties; className?: string } {
  if (!min && !max) return {}
  const style = { ...(min && { '--min': ofRow(min) }), ...(max && { '--max': ofRow(max) }) } as CSSProperties
  return { style, className: [min && 'min-w-(--min)', max && 'max-w-(--max)'].filter(Boolean).join(' ') }
}
