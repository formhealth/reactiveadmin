import { ChevronLeft, ChevronRight } from 'lucide-react'
import type { IndexMeta } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'

type PaginationProps = {
  meta: IndexMeta
  rowCount: number
  perPageOptions: number[]
  onPage: (page: number) => void
  onPerPage: (perPage: number) => void
}

export function Pagination({ meta, rowCount, perPageOptions, onPage, onPerPage }: PaginationProps) {
  const { page, per_page, total_count, total_pages, has_next_page } = meta
  const first = (page - 1) * per_page + 1
  // AA can switch totals off (pagination_total false): only the next page's existence is known then.
  const counted = total_count != null && total_pages != null
  const last = counted ? Math.min(page * per_page, total_count) : first + rowCount - 1
  const hasNext = counted ? page < total_pages : !!has_next_page
  return (
    <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-2 text-sm text-muted-foreground">
      <span className="tabular-nums">
        Showing {first.toLocaleString()} to {last.toLocaleString()}
        {counted && ` of ${total_count.toLocaleString()}`}
      </span>
      <div className="flex items-center gap-2">
        {perPageOptions.length > 0 && (
        <Select value={String(per_page)} onValueChange={(v) => onPerPage(Number(v))}>
          <SelectTrigger size="sm" aria-label="Rows per page">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {perPageOptions.map((n) => (
              <SelectItem key={n} value={String(n)}>
                {n} per page
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        )}
        <Button variant="outline" size="icon-sm" aria-label="Previous page" disabled={page <= 1} onClick={() => onPage(page - 1)}>
          <ChevronLeft />
        </Button>
        <span className="min-w-20 text-center tabular-nums">{counted ? `Page ${page} of ${total_pages}` : `Page ${page}`}</span>
        <Button variant="outline" size="icon-sm" aria-label="Next page" disabled={!hasNext} onClick={() => onPage(page + 1)}>
          <ChevronRight />
        </Button>
      </div>
    </div>
  )
}
