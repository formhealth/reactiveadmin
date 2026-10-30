import { useEffect, useMemo, useState, type KeyboardEvent, type ReactNode } from 'react'
import { ChevronRight, ExternalLink, LayoutList } from 'lucide-react'
import { useQueryClient } from '@tanstack/react-query'
import { Link, useLocation, useNavigate } from 'react-router'
import { getGetResourceMetaQueryOptions } from '@/api/generated/core'
import type { MenuItem } from '@/api/generated/model'
import { META_STALE, useMapClassic } from '@/hooks/useManifest'
import { useStoredState } from '@/hooks/useStoredState'
import { fullPath, groupRoute, hereOf, menuRoute, pruneMenu, searchMenu, trailTo, type MenuLeaf } from '@/lib/menu'
import { cn } from '@/lib/utils'
import { MenuIcon } from './MenuIcon'

const BASE = 12
const STEP = 16
// The overlay allows three levels; anything deeper is drawn flat at the third level.
const MAX_LEVEL = 2

const rowClass =
  'relative flex h-8 w-full items-center gap-2 pr-3 text-left text-sm leading-5 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring'
const topClass = 'font-semibold text-foreground hover:bg-muted'
const activeClass = 'bg-primary/10 font-semibold text-foreground'
const Gutter = () => <span aria-hidden className="size-4 shrink-0" />
const indent = (depth: number) => BASE + STEP * Math.min(depth, MAX_LEVEL)

function Highlight({ text, term }: { text: string; term: string }) {
  const word = term.split(/\s+/).find(Boolean) ?? ''
  const at = word ? text.toLowerCase().indexOf(word.toLowerCase()) : -1
  if (at < 0) return <span className="truncate">{text}</span>
  return (
    <span className="truncate">
      {text.slice(0, at)}
      <mark className="rounded-sm bg-primary/15 font-semibold text-inherit">{text.slice(at, at + word.length)}</mark>
      {text.slice(at + word.length)}
    </span>
  )
}

const visibleIds = (items: MenuItem[], isOpen: (id: string) => boolean): string[] =>
  items.flatMap((i) => (i.children.length ? [i.id, ...(isOpen(i.id) ? visibleIds(i.children, isOpen) : [])] : [i.id]))

type MenuTreeProps = { items: MenuItem[]; term?: string; onNavigate?: () => void }

export function MenuTree({ items, term = '', onNavigate }: MenuTreeProps) {
  const { pathname } = useLocation()
  const here = useMemo(() => hereOf(pathname), [pathname])
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const mapUrl = useMapClassic()
  const query = term.trim()
  const searching = query !== ''
  const tree = useMemo(() => pruneMenu(items), [items])
  const found = useMemo(() => (searching ? searchMenu(items, query) : undefined), [items, query, searching])
  const trail = useMemo(() => trailTo(items, here), [items, here])
  const activeId = trail.at(-1)
  const [open, setOpen] = useStoredState<string[]>('ra:menu:open', [])
  const [focusId, setFocusId] = useState<string>()
  const isOpen = (id: string) => open.includes(id)

  const trailKey = trail.join('/')
  useEffect(() => {
    const groups = trailKey.split('/').filter(Boolean)
    setOpen((prev) => (groups.every((id) => prev.includes(id)) ? prev : [...new Set([...prev, ...groups])]))
  }, [trailKey, setOpen])

  const ids = found ? [...found.groups, ...found.leaves].map((e) => e.id) : visibleIds(tree, isOpen)
  const tabbable = [focusId, activeId].find((id) => id && ids.includes(id)) ?? ids[0]
  const toggle = (id: string) => setOpen((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]))
  const warm = (resource?: string | null) => resource && queryClient.prefetchQuery(getGetResourceMetaQueryOptions(resource, { query: { staleTime: META_STALE } }))

  const onKeyDown = (e: KeyboardEvent<HTMLUListElement>) => {
    const nodes = [...e.currentTarget.querySelectorAll<HTMLElement>('[data-tree-item]')]
    const i = nodes.indexOf(document.activeElement as HTMLElement)
    if (i < 0) return
    const el = nodes[i]
    const expanded = el.getAttribute('aria-expanded')
    const go = (target?: HTMLElement) => {
      if (!target) return
      e.preventDefault()
      target.focus()
    }
    if (e.key === 'ArrowDown') go(nodes[i + 1])
    else if (e.key === 'ArrowUp') go(nodes[i - 1])
    else if (e.key === 'Home') go(nodes[0])
    else if (e.key === 'End') go(nodes.at(-1))
    else if (e.key === 'Enter' && e.shiftKey && el.dataset.group) {
      e.preventDefault()
      onNavigate?.()
      navigate(groupRoute(el.dataset.id!))
    } else if (e.key === 'ArrowRight') {
      if (expanded === 'false') {
        e.preventDefault()
        toggle(el.dataset.id!)
      } else if (expanded === 'true') go(nodes[i + 1])
    } else if (e.key === 'ArrowLeft') {
      if (expanded === 'true') {
        e.preventDefault()
        toggle(el.dataset.id!)
      } else go(nodes.find((n) => n.dataset.id === el.dataset.parent))
    }
  }

  const render = (list: MenuItem[], depth: number, parent?: string): ReactNode =>
    list.map((item) => {
      const aria = {
        'data-tree-item': '',
        'data-id': item.id,
        'data-parent': parent,
        'aria-level': Math.min(depth, MAX_LEVEL) + 1,
        tabIndex: item.id === tabbable ? 0 : -1,
        onFocus: () => setFocusId(item.id),
      }
      const iconName = depth === 0 ? item.icon : undefined

      if (item.children.length) {
        const expanded = isOpen(item.id)
        const active = item.id === activeId
        return (
          <li key={item.id} role="none">
            <div className="group/row relative">
              <button
                type="button"
                role="treeitem"
                aria-expanded={expanded}
                aria-current={active ? 'page' : undefined}
                data-group=""
                title={item.description ?? undefined}
                {...aria}
                onClick={() => toggle(item.id)}
                style={{ paddingLeft: indent(depth) }}
                className={cn(rowClass, active ? activeClass : topClass, 'pr-9')}
              >
                {active && <span aria-hidden className="absolute inset-y-0 left-0 w-[3px] bg-primary" />}
                <ChevronRight aria-hidden className={cn('size-4 shrink-0 text-muted-foreground transition-transform motion-reduce:transition-none', expanded && 'rotate-90')} />
                <MenuIcon name={iconName} className="text-muted-foreground" />
                <span className="truncate">{item.label}</span>
              </button>
              <Link
                to={groupRoute(item.id)}
                tabIndex={-1}
                aria-hidden
                aria-label={`${item.label} overview`}
                title="Overview (Shift+Enter)"
                onClick={onNavigate}
                className="absolute top-1 right-2 flex size-6 items-center justify-center rounded-sm text-muted-foreground opacity-0 outline-none group-focus-within/row:opacity-100 group-hover/row:opacity-100 hover:bg-background hover:text-foreground focus-visible:opacity-100 focus-visible:ring-2 focus-visible:ring-ring"
              >
                <LayoutList aria-hidden className="size-3.5" />
              </Link>
            </div>
            {expanded && (
              <ul
                role="group"
                style={{ '--guide': `${indent(depth) + 8}px` } as React.CSSProperties}
                className="relative before:absolute before:inset-y-0 before:left-(--guide) before:w-px before:bg-border"
              >
                {render(item.children, depth + 1, item.id)}
              </ul>
            )}
          </li>
        )
      }

      const active = item.id === activeId
      const className = cn(rowClass, active ? activeClass : depth === 0 ? topClass : 'text-muted-foreground hover:bg-muted hover:text-foreground')
      const style = { paddingLeft: indent(depth) }
      const bar = active && <span aria-hidden className="absolute inset-y-0 left-0 w-[3px] bg-primary" />
      const to = menuRoute(item, mapUrl)
      return (
        <li key={item.id} role="none">
          {to ? (
            <Link
              to={to}
              role="treeitem"
              aria-current={active ? 'page' : undefined}
              title={item.description ?? undefined}
              {...aria}
              onFocus={() => {
                aria.onFocus()
                warm(item.resource)
              }}
              onPointerEnter={() => warm(item.resource)}
              onClick={onNavigate}
              style={style}
              className={className}
            >
              {bar}
              <Gutter />
              <MenuIcon name={iconName} className="text-muted-foreground" />
              <span className="truncate">{item.label}</span>
            </Link>
          ) : (
            <a href={item.url ?? undefined} target="_blank" rel="noopener noreferrer" role="treeitem" {...aria} style={style} className={className}>
              <Gutter />
              <span className="truncate">{item.label}</span>
              <ExternalLink aria-hidden className="ml-auto size-3.5 shrink-0 text-muted-foreground" />
              <span className="sr-only">(opens in a new tab)</span>
            </a>
          )}
        </li>
      )
    })

  if (found) {
    const results: (MenuLeaf & { group?: boolean })[] = [...found.groups.map((g) => ({ ...g, group: true })), ...found.leaves]
    if (results.length === 0) return <p className="px-4 py-3 text-sm text-muted-foreground">No menu items match "{query}".</p>
    return (
      <ul aria-label="Menu results" onKeyDown={onKeyDown}>
        {results.map((entry) => {
          const to = entry.group ? groupRoute(entry.id) : menuRoute(entry, mapUrl)
          const aria = { 'data-tree-item': '', 'data-id': entry.id, tabIndex: entry.id === tabbable ? 0 : -1, onFocus: () => setFocusId(entry.id) }
          const body = (
            <>
              <span className="flex min-w-0 flex-col">
                <Highlight text={entry.label} term={query} />
                {entry.path.length > 0 && <span className="truncate text-xs text-muted-foreground">{entry.path.join(' / ')}</span>}
              </span>
              {entry.group ? <span className="ml-auto shrink-0 text-xs text-muted-foreground">Overview</span> : !to && <ExternalLink aria-hidden className="ml-auto size-3.5 shrink-0 text-muted-foreground" />}
            </>
          )
          const className = 'flex min-h-9 w-full items-center gap-2 px-4 py-1 text-left text-sm outline-none hover:bg-muted focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring'
          return (
            <li key={`${entry.group ? 'g' : 'l'}-${entry.id}`} title={fullPath(entry)}>
              {to ? (
                <Link to={to} {...aria} onClick={onNavigate} onPointerEnter={() => warm(entry.resource)} className={className}>
                  {body}
                </Link>
              ) : (
                <a href={entry.url ?? undefined} target="_blank" rel="noopener noreferrer" {...aria} className={className}>
                  {body}
                </a>
              )}
            </li>
          )
        })}
      </ul>
    )
  }

  return (
    <ul role="tree" aria-label="Menu" onKeyDown={onKeyDown}>
      {render(tree, 0)}
    </ul>
  )
}
