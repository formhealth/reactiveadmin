import { useCallback, useDeferredValue, useId, useMemo, useRef, useState } from 'react'
import { JsonViewer, type CustomNodeDefinition, type CustomTextDefinitions, type JsonViewerHandle, type NodeData } from 'json-edit-react'
import { ChevronsDownUp, ChevronsUpDown, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { cn } from '@/lib/utils'
import { onCopy, maskedNode, treeButtons, treeProps } from './options'
import { pathString } from './paths'
import { countMatches, leafCount, PAGE_SIZE, paginate, parseMoreMarker, type Limits } from './tree'
import { useSearchHighlight } from './useSearchHighlight'
import { useTreeKeyboard } from './useTreeKeyboard'
import './json.css'

// A paginated array carries one marker item; the count should still be the real length.
const countText: CustomTextDefinitions = Object.fromEntries(
  ['ITEM_SINGLE', 'ITEMS_MULTIPLE'].map((key) => [
    key,
    ({ value, size }: NodeData) => {
      const marker = Array.isArray(value) ? parseMoreMarker(value.at(-1)) : undefined
      if (!marker || size === null) return null
      const total = size - 1 + marker.remaining
      return `${total} ${total === 1 ? 'item' : 'items'}`
    },
  ]),
)

const SMALL_LEAVES = 10

type Props = {
  value: unknown
  label?: string
  defaultDepth?: number
  searchable?: boolean
  maxHeight?: string
  className?: string
}

export function JsonView({ value, label = 'JSON', defaultDepth = 2, searchable = true, maxHeight, className }: Props) {
  const [term, setTerm] = useState('')
  const [limits, setLimits] = useState<Limits>({})
  const handle = useRef<JsonViewerHandle>(null)
  const highlight = `ra-json-${useId().replace(/\W/g, '')}`
  // A few values read at a glance; search and expand-all would only add noise.
  const small = leafCount(value) <= SMALL_LEAVES
  const query = useDeferredValue(searchable && !small ? term.trim() : '')
  const tree = useTreeKeyboard<HTMLDivElement>(label)
  useSearchHighlight(tree.ref, query, highlight)

  // Hidden array items would never match, so a search looks at the full value.
  const data = useMemo(() => (query ? value : paginate(value, limits)), [value, limits, query])
  const matches = useMemo(() => countMatches(value, query), [value, query])

  const showMore = useCallback((path: (string | number)[]) => {
    const key = pathString(path)
    setLimits((prev) => ({ ...prev, [key]: (prev[key] ?? PAGE_SIZE) + PAGE_SIZE }))
  }, [])

  const nodes = useMemo<CustomNodeDefinition[]>(
    () => [
      maskedNode,
      {
        condition: ({ value }) => !!parseMoreMarker(value),
        component: ({ value }) => {
          const marker = parseMoreMarker(value)!
          const next = Math.min(PAGE_SIZE, marker.remaining)
          return (
            <Button type="button" variant="outline" size="xs" onClick={() => showMore(marker.path)}>
              Show {next} more
              <span className="font-normal text-muted-foreground">({marker.remaining} left)</span>
            </Button>
          )
        },
        showOnEdit: false,
        showEditTools: false,
        showKey: false,
      },
    ],
    [showMore],
  )

  const collapseAll = () => handle.current?.collapse([{ path: [], collapsed: true, includeChildren: true }, { path: [], collapsed: false, includeChildren: false }])
  const expandAll = () => handle.current?.collapse({ path: [], collapsed: false, includeChildren: true })

  return (
    <div className={cn('flex w-full min-w-0 flex-col gap-2', className)}>
      {!small && (
        <div className="flex flex-wrap items-center gap-2">
          {searchable && (
            <div className="relative min-w-40 max-w-xs flex-1">
              <Search className="pointer-events-none absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground" aria-hidden />
              <Input type="search" value={term} onChange={(e) => setTerm(e.target.value)} placeholder="Search keys and values" aria-label={`Search ${label}`} className="h-8 pl-8 text-xs" />
            </div>
          )}
          <Button type="button" variant="outline" size="xs" onClick={expandAll}>
            <ChevronsUpDown />
            Expand all
          </Button>
          <Button type="button" variant="outline" size="xs" onClick={collapseAll}>
            <ChevronsDownUp />
            Collapse all
          </Button>
          {query && (
            <span role="status" className="text-xs text-muted-foreground">
              {matches === 0 ? 'No matches' : `${matches} ${matches === 1 ? 'match' : 'matches'}`}
            </span>
          )}
        </div>
      )}
      <style>{`::highlight(${highlight}) { background-color: color-mix(in srgb, var(--warning) 35%, transparent); color: inherit; }`}</style>
      <div {...tree} className={cn('ra-json rounded-md border bg-muted/40 p-2', maxHeight && 'overflow-auto')} style={{ maxHeight }}>
        <JsonViewer
          data={data}
          collapse={query ? false : defaultDepth}
          searchText={query}
          searchFilter="all"
          searchDebounceTime={0}
          {...treeProps}
          customNodeDefinitions={nodes}
          customButtons={treeButtons}
          customText={countText}
          onCopy={onCopy}
          editorRef={handle}
        />
      </div>
    </div>
  )
}
