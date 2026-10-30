import { Skeleton } from '@/components/ui/skeleton'

export function FormSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-hidden>
      {[3, 2].map((rows, i) => (
        <div key={i} className="flex flex-col gap-5 rounded-lg border bg-card p-5">
          <Skeleton className="h-5 w-48" />
          {Array.from({ length: rows }, (_, r) => (
            <div key={r} className="flex max-w-xl flex-col gap-1.5">
              <Skeleton className="h-4 w-28" />
              <Skeleton className="h-8 w-full" />
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}
