import { Skeleton } from '@/components/ui/skeleton'

export function RouteSkeleton() {
  return (
    <div className="flex flex-col gap-4" role="status" aria-label="Loading page">
      <Skeleton className="h-8 w-64" />
      <Skeleton className="h-64 w-full" />
    </div>
  )
}
