import { createContext, use, useEffect } from 'react'
import type { Capability, Screen } from '@/lib/shortcuts'

export type Scope = { screen: Screen; caps: Capability[] }

export const anywhere: Scope = { screen: 'any', caps: [] }
export const ScopeContext = createContext<(scope: Scope) => void>(() => {})

// Screens say what they offer so the shortcuts dialog matches what the keys do right now.
export function useShortcutScope(screen: Screen, caps: Capability[]) {
  const setScope = use(ScopeContext)
  const key = caps.join()
  useEffect(() => {
    setScope({ screen, caps: key ? (key.split(',') as Capability[]) : [] })
    return () => setScope(anywhere)
  }, [setScope, screen, key])
}
