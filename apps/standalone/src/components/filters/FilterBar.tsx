import { SlidersHorizontal, X } from 'lucide-react'
import type { Filter } from '@/api/generated/model'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet'
import type { QChanges } from '@/hooks/useListState'
import { rangeLabel } from '@/lib/dateRange'
import { asList, asText, type Query } from '@/lib/list'
import { CheckboxesFilter, SelectFilter, TextFilter, TypeaheadFilter, type FilterControlProps } from './controls'
import { DateRangeFilter } from './DateRangeFilter'

const controls: Record<Filter['control'], (props: FilterControlProps) => React.ReactNode> = {
  text: TextFilter,
  number: TextFilter,
  select: SelectFilter,
  boolean: SelectFilter,
  typeahead: TypeaheadFilter,
  checkboxes: CheckboxesFilter,
  date_range: DateRangeFilter,
}

type Chip = { id: string; text: string; clear: QChanges }

function chipFor(filter: Filter, q: Query): Chip | undefined {
  const { name, label, range } = filter
  if (filter.control === 'date_range' && range) {
    const [from, to] = [asText(q[range.from]), asText(q[range.to])]
    return from || to
      ? { id: name, text: `${label}: ${rangeLabel(from, to)}`, clear: { [range.from]: undefined, [range.to]: undefined } }
      : undefined
  }
  const predicate = filter.predicates?.find((p) => q[p.param])
  const param = predicate?.param ?? filter.param ?? name
  const values = asList(q[param])
  if (values.length === 0) return
  const value = values.map((v) => filter.options?.find((o) => o.value === v)?.label ?? v).join(', ')
  const shown = value
  return { id: name, text: `${label}${predicate ? ` ${predicate.label.toLowerCase()}` : ':'} ${shown}`, clear: { [param]: undefined } }
}

type FilterBarProps = {
  filters: Filter[]
  q: Query
  setQ: FilterControlProps['setQ']
  clearAll: () => void
  compact?: boolean
}

export function FilterBar({ filters, q, setQ, clearAll, compact }: FilterBarProps) {
  const chips = filters.map((f) => chipFor(f, q)).filter((c): c is Chip => !!c)
  const fields = filters.map((filter) => {
    const Control = controls[filter.control]
    return <Control key={filter.name} filter={filter} q={q} setQ={setQ} />
  })

  return (
    <div className="flex flex-col gap-2">
      {compact ? (
        <div>
          <Sheet>
            <SheetTrigger asChild>
              <Button variant="outline">
                <SlidersHorizontal />
                Filters{chips.length > 0 && ` (${chips.length})`}
              </Button>
            </SheetTrigger>
            <SheetContent side="right" aria-describedby={undefined} className="gap-0 p-0">
              <SheetHeader>
                <SheetTitle>Filters</SheetTitle>
              </SheetHeader>
              <div id="filters" className="flex flex-1 flex-col gap-3 overflow-y-auto p-4 [&_input]:w-full [&>*>button]:w-full [&>button]:w-full">
                {fields}
              </div>
            </SheetContent>
          </Sheet>
        </div>
      ) : (
        <div id="filters" className="flex flex-wrap items-center gap-2">
          {fields}
        </div>
      )}
      {chips.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          {chips.map(({ id, text, clear }) => (
            <Badge key={id} variant="secondary" className="h-6 gap-1 pr-1 text-sm">
              {text}
              <button type="button" aria-label={`Remove ${text}`} onClick={() => setQ(clear)} className="rounded-sm p-0.5 hover:bg-foreground/10 focus-visible:ring-2 focus-visible:ring-ring">
                <X className="size-3" />
              </button>
            </Badge>
          ))}
          <Button variant="ghost" size="sm" onClick={clearAll}>
            Clear all
          </Button>
        </div>
      )}
    </div>
  )
}
