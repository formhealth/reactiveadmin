import { useState } from 'react'
import { ChevronsUpDown } from 'lucide-react'
import type { Filter, Option } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useDebouncedCommit } from '@/hooks/useDebouncedCommit'
import type { QChanges } from '@/hooks/useListState'
import { OptionList } from '@/forms/fields/OptionList'
import { useOptionSource } from '@/forms/fields/useOptionSource'
import { asList, asText, type Query } from '@/lib/list'
import { cn } from '@/lib/utils'

export type FilterControlProps = {
  filter: Filter
  q: Query
  setQ: (changes: QChanges) => void
}

const ANY = '__any__'
const booleanOptions: Option[] = [
  { label: 'Yes', value: 'true' },
  { label: 'No', value: 'false' },
]

export function TextFilter({ filter, q, setQ }: FilterControlProps) {
  const predicates = filter.predicates?.length ? filter.predicates : [{ param: filter.param ?? filter.name, label: 'Equals' }]
  const active = predicates.find((p) => q[p.param]) ?? predicates[0]
  const [value, change] = useDebouncedCommit(asText(q[active.param]), (next) => setQ({ [active.param]: next || undefined }))

  const switchPredicate = (param: string) => setQ({ [active.param]: undefined, [param]: value || undefined })

  return (
    <div className="flex">
      {predicates.length > 1 && (
        <Select value={active.param} onValueChange={switchPredicate}>
          <SelectTrigger size="default" className="rounded-r-none border-r-0" aria-label={`${filter.label} predicate`}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {predicates.map((p) => (
              <SelectItem key={p.param} value={p.param}>
                {p.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )}
      <Input
        value={value}
        onChange={(e) => change(e.target.value)}
        placeholder={filter.label}
        aria-label={filter.label}
        type={filter.control === 'number' ? 'number' : 'text'}
        className={predicates.length > 1 ? 'w-40 rounded-l-none' : 'w-44'}
      />
    </div>
  )
}

export function SelectFilter({ filter, q, setQ }: FilterControlProps) {
  const param = filter.param ?? filter.name
  const options = filter.options ?? (filter.control === 'boolean' ? booleanOptions : [])
  return (
    <Select value={asText(q[param]) || ANY} onValueChange={(v) => setQ({ [param]: v === ANY ? undefined : v })}>
      <SelectTrigger aria-label={filter.label} className="min-w-40">
        <span className="text-muted-foreground">{filter.label}:</span>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={ANY}>Any</SelectItem>
        {options.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

export function TypeaheadFilter({ filter, q, setQ }: FilterControlProps) {
  const [open, setOpen] = useState(false)
  const param = filter.param ?? filter.name
  const multiple = !!filter.multiple
  const selected = asList(q[param])
  const remote = filter.options_path
  const source = useOptionSource({ path: remote, inline: filter.options ?? [], selected, open })

  const pick = (option: { label: string; value: string }) => {
    source.remember(option)
    if (!multiple) {
      setQ({ [param]: option.value })
      setOpen(false)
    } else setQ({ [param]: selected.includes(option.value) ? selected.filter((v) => v !== option.value) : [...selected, option.value] })
  }

  const summary = selected.length === 0 ? 'Any' : selected.length === 1 ? source.labelOf(selected[0]) : `${selected.length} selected`

  return (
    <Popover
      open={open}
      onOpenChange={(next) => {
        setOpen(next)
        if (!next) source.setTerm('')
      }}
    >
      <PopoverTrigger asChild>
        <Button variant="outline" role="combobox" aria-expanded={open} aria-label={filter.label} className="min-w-40 justify-between font-normal">
          <span className="text-muted-foreground">{filter.label}:</span>
          <span className="flex-1 truncate text-left">{summary}</span>
          <ChevronsUpDown className="size-4 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" aria-label={filter.label} className="w-72 p-0">
        <OptionList
          source={source}
          inline={filter.options ?? []}
          remote={!!remote}
          selected={selected}
          placeholder={`Search ${filter.label.toLowerCase()}…`}
          onPick={pick}
          onClear={() => (setQ({ [param]: undefined }), setOpen(false))}
          clearLabel="Any"
        />
      </PopoverContent>
    </Popover>
  )
}

// A short list of options shown inline as toggleable chips; any number can be on.
export function CheckboxesFilter({ filter, q, setQ }: FilterControlProps) {
  const param = filter.param ?? filter.name
  const selected = asList(q[param])
  const toggle = (value: string) => setQ({ [param]: selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value] })

  return (
    <div role="group" aria-label={filter.label} className="flex flex-wrap items-center gap-1.5">
      <span className="text-sm text-muted-foreground">{filter.label}:</span>
      {(filter.options ?? []).map((option) => {
        const on = selected.includes(option.value)
        return (
          <button
            key={option.value}
            type="button"
            aria-pressed={on}
            onClick={() => toggle(option.value)}
            className={cn(
              'inline-flex h-8 items-center gap-1.5 rounded-md border px-2.5 text-sm outline-none hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring',
              on ? 'border-primary bg-primary/10 font-medium text-foreground' : 'bg-card text-muted-foreground',
            )}
          >
            {option.label}
          </button>
        )
      })}
    </div>
  )
}
