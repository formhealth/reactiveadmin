import { lazy, Suspense, type ComponentProps } from 'react'
import { Skeleton } from '@/components/ui/skeleton'

// json-edit-react and jsondiffpatch are large, and most pages never open a tree, diff or editor.
const JsonViewer = lazy(() => import('./JsonView').then((m) => ({ default: m.JsonView })))
const JsonDiffer = lazy(() => import('./JsonDiff').then((m) => ({ default: m.JsonDiff })))
const JsonTreeEditor = lazy(() => import('./JsonEditor').then((m) => ({ default: m.JsonEditor })))

const loading = <Skeleton className="h-24 w-full" role="status" aria-label="Loading JSON" />

export function LazyJsonView(props: ComponentProps<typeof JsonViewer>) {
  return (
    <Suspense fallback={loading}>
      <JsonViewer {...props} />
    </Suspense>
  )
}

export function LazyJsonDiff(props: ComponentProps<typeof JsonDiffer>) {
  return (
    <Suspense fallback={loading}>
      <JsonDiffer {...props} />
    </Suspense>
  )
}

export function LazyJsonEditor(props: ComponentProps<typeof JsonTreeEditor>) {
  return (
    <Suspense fallback={loading}>
      <JsonTreeEditor {...props} />
    </Suspense>
  )
}
