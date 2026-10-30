import { useEffect, useRef, useState } from 'react'

// Local value that follows `external` (the URL) and commits edits after `delay` ms.
export function useDebouncedCommit(external: string, commit: (value: string) => void, delay = 300) {
  const [value, setValue] = useState(external)
  const [seen, setSeen] = useState(external)
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined)

  if (external !== seen) {
    setSeen(external)
    setValue(external)
  }

  useEffect(() => () => clearTimeout(timer.current), [])

  const change = (next: string) => {
    setValue(next)
    clearTimeout(timer.current)
    timer.current = setTimeout(() => commit(next), delay)
  }
  return [value, change] as const
}
