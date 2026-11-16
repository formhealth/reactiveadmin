import { useEffect, useEffectEvent } from 'react'
import { plainShortcut, type ShortcutId } from '@/lib/shortcuts'

// Where a bare key means something else: text entry, and widgets that own the keys while open.
const OWNS_KEYS = '[role=dialog],[role=alertdialog],[role=menu],[role=listbox],[role=combobox]'
// The sidebar menu owns the movement keys while focus is inside it.
const MENU_ITEM = '[data-tree-item]'
// Embedded widgets that own the keys while focused: the JSON viewer's tree and a disclosure's summary.
const EMBEDDED = '[role=tree],summary'
const OPEN_MODAL = '[role=dialog][data-state=open],[role=alertdialog][data-state=open]'

const isTyping = (el: EventTarget | null) =>
  el instanceof HTMLElement && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) || !!el.closest(OWNS_KEYS))

const isMenuItem = (el: EventTarget | null) => el instanceof Element && !!el.closest(MENU_ITEM)

const isEmbedded = (el: EventTarget | null) => el instanceof Element && !!el.closest(EMBEDDED) && !isMenuItem(el)

type Handlers = Partial<Record<ShortcutId, (e: KeyboardEvent) => void>>

export function useHotkeys(handlers: Handlers) {
  const onKeyDown = useEffectEvent((e: KeyboardEvent) => {
    if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey || isTyping(e.target) || isEmbedded(e.target) || document.querySelector(OPEN_MODAL)) return
    const ids = (Object.keys(handlers) as ShortcutId[]).filter((id) => handlers[id])
    const shortcut = plainShortcut(e.key, ids)
    if (!shortcut || (shortcut.screen !== 'any' && isMenuItem(e.target))) return
    handlers[shortcut.id]!(e)
  })
  useEffect(() => {
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])
}
