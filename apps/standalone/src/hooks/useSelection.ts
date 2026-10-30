import { useState } from 'react'

export type Selection = {
  ids: Set<string>
  toggle: (id: string) => void
  togglePage: (ids: string[], on: boolean) => void
  clear: () => void
}

// Survives paging and sorting, but resets with `resetKey` (resource, scope, filters) so a hidden
// selection can never be acted on after the view changed.
export function useSelection(resetKey: string): Selection {
  const [state, setState] = useState({ key: resetKey, ids: new Set<string>() })
  const ids = state.key === resetKey ? state.ids : new Set<string>()
  const update = (change: (next: Set<string>) => void) => {
    const next = new Set(ids)
    change(next)
    setState({ key: resetKey, ids: next })
  }
  return {
    ids,
    toggle: (id) => update((next) => void (next.delete(id) || next.add(id))),
    togglePage: (page, on) => update((next) => page.forEach((id) => (on ? next.add(id) : next.delete(id)))),
    clear: () => update((next) => next.clear()),
  }
}
