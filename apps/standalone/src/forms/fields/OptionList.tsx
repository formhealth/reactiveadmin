import type { ClipboardEvent, ReactNode } from 'react'
import type { Option } from '@/api/generated/model'
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command'
import { isIdLike } from '@/lib/ids'
import type { OptionSource } from './useOptionSource'

const LOAD_MORE = '__load_more__'

function Row({ option }: { option: Option }) {
  return (
    <>
      <span className="truncate">{option.label}</span>
      {option.hint && <span className="min-w-0 truncate text-xs text-muted-foreground">{option.hint}</span>}
    </>
  )
}

type OptionListProps = {
  source: OptionSource
  // Inline options are filtered in the browser; remote ones are searched by the server.
  inline: Option[]
  remote: boolean
  selected: string[]
  placeholder: string
  onPick: (option: Option) => void
  // A "None" row that clears a single selection.
  onClear?: () => void
  clearLabel?: string
  freeText?: boolean
}

// The body of every typeahead: what's selected first, then recent picks, then results with a way to page on.
export function OptionList({ source, inline, remote, selected, placeholder, onPick, onClear, clearLabel = 'None', freeText }: OptionListProps) {
  const { term, setTerm } = source
  const typed = term.trim()
  const choices = remote ? source.found : inline
  const chosen = selected.flatMap((value) => source.optionOf(value) ?? [])
  const shown = new Set(chosen.map((o) => o.value))
  const recent = remote && !typed ? source.recent.filter((o) => !shown.has(o.value)) : []
  recent.forEach((o) => shown.add(o.value))
  const rest = choices.filter((o) => !shown.has(o.value))
  const offerTyped = freeText && typed && ![...chosen, ...choices].some((o) => o.label.toLowerCase() === typed.toLowerCase())
  const isSelected = (option: Option) => selected.includes(option.value)

  const item = (option: Option) => (
    <CommandItem key={option.value} value={remote ? option.value : `${option.label} ${option.hint ?? ''}`} onSelect={() => onPick(option)} data-checked={isSelected(option)}>
      <Row option={option} />
    </CommandItem>
  )

  // A pasted id is looked up directly, so it works even when the search can't match on it.
  const onPaste = (event: ClipboardEvent<HTMLInputElement>) => {
    const text = event.clipboardData.getData('text').trim()
    if (!remote || !isIdLike(text)) return
    event.preventDefault()
    setTerm(text)
    source.lookup(text).then((option) => option && onPick(option), () => undefined)
  }

  return (
    <Command shouldFilter={!remote}>
      <CommandInput value={term} onValueChange={setTerm} onPaste={onPaste} placeholder={placeholder} />
      <div role="status" className="empty:hidden">
        {remote && source.searching && <p className="px-3 py-2 text-sm text-muted-foreground">Searching…</p>}
        {remote && source.rateLimited && !source.searching && <p className="px-3 py-2 text-sm text-muted-foreground">Searching too fast. Pause for a moment, then keep typing.</p>}
      </div>
      <CommandList>
        {!offerTyped && !source.searching && !(remote && source.rateLimited) && <CommandEmpty>No matches.</CommandEmpty>}
        {onClear && selected.length > 0 && (
          <CommandItem value="__none__" onSelect={onClear} className="text-muted-foreground">
            {clearLabel}
          </CommandItem>
        )}
        {chosen.length > 0 && <CommandGroup heading={selected.length > 1 ? 'Selected' : undefined}>{chosen.map(item)}</CommandGroup>}
        {recent.length > 0 && <CommandGroup heading="Recent">{recent.map(item)}</CommandGroup>}
        {rest.length > 0 && <CommandGroup heading={chosen.length + recent.length > 0 ? (typed ? 'Matches' : 'All') : undefined}>{rest.map(item)}</CommandGroup>}
        {offerTyped && (
          <CommandItem value={`__typed__${typed}`} onSelect={() => onPick({ label: typed, value: typed })} forceMount>
            Add “{typed}” as typed
          </CommandItem>
        )}
        {remote && source.hasMore && (
          <CommandItem value={LOAD_MORE} forceMount disabled={source.loadingMore} onSelect={source.loadMore} className="justify-center text-muted-foreground">
            {source.loadingMore ? 'Loading…' : 'Load more'}
          </CommandItem>
        )}
        {remote && source.truncated && (
          <Footer>{source.hasMore ? `Showing ${source.found.length} matches so far.` : `Showing the first ${source.found.length} matches. Keep typing to narrow them.`}</Footer>
        )}
      </CommandList>
    </Command>
  )
}

const Footer = ({ children }: { children: ReactNode }) => <p className="px-3 py-2 text-xs text-muted-foreground">{children}</p>
