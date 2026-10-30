import { lazy, Suspense, type ComponentType } from 'react'
import { Skeleton } from '@/components/ui/skeleton'
import type { NodeProps } from './Node'

// Forms, frames, media and sanitized HTML are rare in a table, so their code loads when such a node first renders.
export function lazyNode(load: () => Promise<ComponentType<NodeProps>>): ComponentType<NodeProps> {
  const Component = lazy(async () => ({ default: await load() }))
  return function LazyNode(props: NodeProps) {
    return (
      <Suspense fallback={<Skeleton className="h-5 w-24" role="status" aria-label="Loading" />}>
        <Component {...props} />
      </Suspense>
    )
  }
}
