import { useCallback, useEffect, useId, useRef, useState, type KeyboardEvent, type MouseEvent } from 'react'

const ROW = '.jer-collection-header-row, .jer-value-main-row'
const INNER = '.jer-collection-inner'

const rowsOf = (root: HTMLElement) => [...root.querySelectorAll<HTMLElement>(ROW)]

// Collapsed branches stay mounted (clipped to zero height), so ask the header that owns each level.
const visible = (row: HTMLElement, root: HTMLElement) => {
  for (let el = row.parentElement; el && el !== root; el = el.parentElement) {
    if (el.matches(INNER) && el.previousElementSibling?.querySelector('.jer-collapse-icon')?.getAttribute('aria-expanded') === 'false') return false
  }
  return true
}

const levelOf = (row: HTMLElement) => {
  let level = 1
  for (let el = row.parentElement; el; el = el.parentElement) if (el.matches(INNER)) level++
  return level
}

// The row to keep active once `row` is unmounted (none) or hidden inside a collapsed branch (the outermost visible header above it).
const survivor = (row: HTMLElement, root: HTMLElement) => {
  if (row.isConnected && visible(row, root)) return row
  if (!row.isConnected) return undefined
  const headers = []
  for (let el = row.parentElement; el && el !== root; el = el.parentElement) {
    const header = el.matches(INNER) ? el.previousElementSibling?.querySelector<HTMLElement>(ROW) ?? undefined : undefined
    if (header) headers.push(header)
  }
  return headers.find((header) => visible(header, root))
}

const toggleOf = (row: HTMLElement) => row.querySelector<HTMLButtonElement>('.jer-collapse-icon')
const press = (row: HTMLElement, label: string) => row.querySelector<HTMLButtonElement>(`.jer-edit-buttons button[aria-label="${label}"]`)?.click()

const nameOf = (row: HTMLElement) => {
  const key = row.querySelector('.jer-key-text')?.textContent?.replace(/:$/, '')
  const rest = row.matches('.jer-collection-header-row')
    ? row.querySelector('.jer-collection-item-count')?.textContent
    : row.querySelector('.jer-input-component')?.textContent
  return [key, rest].filter(Boolean).join(', ') || undefined
}

// Writing an unchanged attribute still queues a mutation record, which would feed the observer below forever.
const mark = (el: HTMLElement, name: string, value: string | null) => {
  if (el.getAttribute(name) === value) return
  if (value === null) el.removeAttribute(name)
  else el.setAttribute(name, value)
}

const SHORTCUTS: Record<string, string> = { c: 'Copy to clipboard', p: 'Copy path', e: 'Edit', a: 'Add', Delete: 'Delete' }

// The viewer's rows are plain divs, so this layers tree semantics (roles, levels, an active row) and
// keyboard control onto them. Keys: arrows/Home/End move, Enter or Space toggles, c copies the value,
// p the path, and in the editor e edits, a adds and Delete removes.
export function useTreeKeyboard<T extends HTMLElement>(label: string) {
  const ref = useRef<T>(null)
  const uid = useId()
  const [activeId, setActiveId] = useState<string>()
  const active = useRef<HTMLElement>(undefined)

  const activate = useCallback((row: HTMLElement | undefined) => {
    active.current?.removeAttribute('data-ra-active')
    active.current = row
    row?.setAttribute('data-ra-active', '')
    row?.scrollIntoView({ block: 'nearest' })
    setActiveId(row?.id)
  }, [])

  useEffect(() => {
    const root = ref.current
    if (!root) return
    let count = 0
    const annotate = () => {
      for (const row of rowsOf(root)) {
        row.id ||= `${uid}-row-${count++}`
        mark(row, 'role', 'treeitem')
        mark(row, 'aria-hidden', visible(row, root) ? null : 'true')
        mark(row, 'aria-level', String(levelOf(row)))
        mark(row, 'aria-label', nameOf(row) ?? null)
        mark(row, 'aria-expanded', toggleOf(row)?.getAttribute('aria-expanded') ?? null)
      }
      // Pagination, edits and collapsing can take the active row away; aria-activedescendant must not outlive it.
      if (active.current && survivor(active.current, root) !== active.current) activate(survivor(active.current, root))
    }
    let frame = 0
    const schedule = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(annotate)
    }
    annotate()
    const observer = new MutationObserver(schedule)
    observer.observe(root, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'aria-expanded'] })
    return () => {
      observer.disconnect()
      cancelAnimationFrame(frame)
    }
  }, [uid, activate])

  const onKeyDown = (event: KeyboardEvent<T>) => {
    const root = ref.current
    // Keys typed into the viewer's own inputs (rename, edit) belong to them.
    if (!root || event.target !== root || event.altKey || event.ctrlKey || event.metaKey) return
    const rows = rowsOf(root).filter((row) => visible(row, root))
    const index = active.current ? rows.indexOf(active.current) : -1
    const row = rows[index]
    const go = (to: number) => activate(rows[Math.min(Math.max(to, 0), rows.length - 1)])
    const expanded = row && toggleOf(row)?.getAttribute('aria-expanded')
    const { key } = event

    if (!row) {
      if (!['ArrowDown', 'ArrowUp', 'ArrowRight', 'Home', 'End'].includes(key)) return
      go(key === 'End' ? rows.length - 1 : 0)
    } else if (key === 'ArrowDown') go(index + 1)
    else if (key === 'ArrowUp') go(index - 1)
    else if (key === 'Home') go(0)
    else if (key === 'End') go(rows.length - 1)
    else if (key === 'ArrowRight') {
      if (expanded === 'false') toggleOf(row)?.click()
      else if (expanded === 'true') go(index + 1)
    } else if (key === 'ArrowLeft') {
      if (expanded === 'true') toggleOf(row)?.click()
      else activate(rows.slice(0, index).findLast((r) => levelOf(r) < levelOf(row)) ?? row)
    } else if (key === 'Enter' || key === ' ') {
      if (toggleOf(row)) toggleOf(row)?.click()
      else press(row, 'Edit')
    } else if (SHORTCUTS[key]) press(row, SHORTCUTS[key])
    else return
    event.preventDefault()
  }

  const onClick = (event: MouseEvent<T>) => {
    const row = (event.target as HTMLElement).closest<HTMLElement>(ROW)
    if (row) activate(row)
  }

  // Activating the first row on focus makes the tree usable from the first arrow press.
  const onFocus = () => {
    const root = ref.current
    if (root && !active.current?.isConnected) activate(rowsOf(root)[0])
  }

  return {
    ref,
    tabIndex: 0,
    role: 'tree',
    'aria-label': `${label} tree`,
    'aria-activedescendant': activeId,
    onKeyDown,
    onClick,
    onFocus,
  }
}
