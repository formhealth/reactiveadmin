import { useState } from 'react'

// Scroll margin keeps a sticky header from covering the row the cursor lands on.
export const cursorClass = 'scroll-mt-12 outline-none data-cursor:outline-2 data-cursor:outline-ring'

export const stepIndex = (current: number, step: 1 | -1, count: number) => Math.min(Math.max(current + step, 0), count - 1)

export type RowCursor = {
  id: string | undefined
  move: (step: 1 | -1) => void
  // Spread on a row's element: roving tabindex, so the current row is the one tab stop and screen readers announce it on focus.
  rowProps: (id: string) => { 'data-row-id': string; 'data-cursor': true | undefined; tabIndex: 0 | -1; onFocus: () => void }
}

// The cursor belongs to one page of rows of one collection: any change to the ids (paging, filtering, a refetch with
// other rows) or to the scope (another resource or parent that happens to list the same ids) drops it.
export function useRowCursor(ids: string[], scope = ''): RowCursor {
  const key = [scope, ...ids].join('\n')
  const [state, setState] = useState({ key, index: -1 })
  if (state.key !== key) setState({ key, index: -1 })
  const index = state.key === key ? state.index : -1
  const select = (next: number) => next !== index && setState({ key, index: next })

  return {
    id: ids[index],
    move: (step) => {
      const next = stepIndex(index, step, ids.length)
      select(next)
      document.querySelector<HTMLElement>(`[data-row-id="${CSS.escape(ids[next] ?? '')}"]`)?.focus()
    },
    rowProps: (id) => ({
      'data-row-id': id,
      'data-cursor': ids[index] === id ? true : undefined,
      // Before the cursor is set, the first row is the tab stop, so Tab reaches the rows at all.
      tabIndex: (ids[index] ?? ids[0]) === id ? 0 : -1,
      onFocus: () => select(ids.indexOf(id)),
    }),
  }
}
