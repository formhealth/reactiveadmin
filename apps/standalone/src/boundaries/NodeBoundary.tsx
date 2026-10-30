import type { ReactNode } from 'react'
import { useLocation } from 'react-router'
import { classicUrl } from '@/lib/classic'
import { useNodeContext } from '@/nodes/context'
import { ErrorBoundary } from './ErrorBoundary'
import { Chip } from './fallbacks'
import { classicHere } from './urls'

export function NodeChip() {
  const { resource, id } = useNodeContext()
  const { pathname } = useLocation()
  return <Chip href={resource ? classicUrl(resource, id) : classicHere(pathname)} />
}

export function NodeBoundary({ type, children }: { type: string; children: ReactNode }) {
  return (
    <ErrorBoundary where={`node:${type}`} fallback={() => <NodeChip />}>
      {children}
    </ErrorBoundary>
  )
}
