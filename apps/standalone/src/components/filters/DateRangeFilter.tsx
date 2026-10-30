import { lazy, Suspense, useState } from 'react'
import { endOfMonth, format, parseISO, startOfMonth, subDays } from 'date-fns'
import { CalendarIcon } from 'lucide-react'
import type { DateRange } from 'react-day-picker'
import { Button } from '@/components/ui/button'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Skeleton } from '@/components/ui/skeleton'
import { useIsWide } from '@/hooks/useMediaQuery'
import { rangeLabel } from '@/lib/dateRange'
import { asText } from '@/lib/list'
import type { FilterControlProps } from './controls'

const DateRangeCalendar = lazy(() => import('./DateRangeCalendar').then((m) => ({ default: m.DateRangeCalendar })))

const ymd = (date: Date) => format(date, 'yyyy-MM-dd')

const presets: [string, () => [Date, Date]][] = [
  ['Today', () => [new Date(), new Date()]],
  ['Last 7 days', () => [subDays(new Date(), 6), new Date()]],
  ['Last 30 days', () => [subDays(new Date(), 29), new Date()]],
  ['This month', () => [startOfMonth(new Date()), endOfMonth(new Date())]],
]

export function DateRangeFilter({ filter, q, setQ }: FilterControlProps) {
  const wide = useIsWide()
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState<DateRange>()
  const { from: fromParam = '', to: toParam = '' } = filter.range ?? {}
  const from = asText(q[fromParam])
  const to = asText(q[toParam])

  const commit = (range?: DateRange) => {
    setQ({ [fromParam]: range?.from && ymd(range.from), [toParam]: range?.to && ymd(range.to) })
    setOpen(false)
  }

  const onOpenChange = (next: boolean) => {
    setOpen(next)
    if (next) setDraft({ from: from ? parseISO(from) : undefined, to: to ? parseISO(to) : undefined })
    else if (draft?.from && !draft.to) commit(draft)
  }

  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverTrigger asChild>
        <Button variant="outline" className="justify-start font-normal">
          <CalendarIcon className="size-4 opacity-60" />
          <span className="text-muted-foreground">{filter.label}:</span>
          {rangeLabel(from, to)}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" aria-label={`${filter.label} range`} className="max-h-[80dvh] w-auto max-w-[calc(100vw-1rem)] gap-0 overflow-auto p-0 sm:flex-row">
        <div className="flex flex-wrap gap-1 border-b p-2 sm:flex-col sm:border-r sm:border-b-0">
          {presets.map(([label, range]) => (
            <Button key={label} variant="ghost" size="sm" className="justify-start" onClick={() => commit({ from: range()[0], to: range()[1] })}>
              {label}
            </Button>
          ))}
          {(from || to) && (
            <Button variant="ghost" size="sm" className="justify-start text-muted-foreground" onClick={() => commit()}>
              Clear
            </Button>
          )}
        </div>
        <Suspense fallback={<Skeleton className="m-2 h-64 w-72" />}>
          <DateRangeCalendar
            mode="range"
            numberOfMonths={wide ? 2 : 1}
            defaultMonth={draft?.from}
            selected={draft}
            onSelect={(range) => (range?.to ? commit(range) : setDraft(range))}
          />
        </Suspense>
      </PopoverContent>
    </Popover>
  )
}
