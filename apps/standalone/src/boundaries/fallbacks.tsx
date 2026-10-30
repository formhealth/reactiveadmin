import { ExternalLink } from 'lucide-react'
import { Button } from '@/components/ui/button'

export function Chip({ href }: { href: string }) {
  return (
    <div role="alert" className="flex items-center justify-between gap-3 rounded-md border border-dashed bg-muted/40 px-3 py-2 text-sm text-muted-foreground">
      <span>Couldn't display this section</span>
      <a href={href} className="inline-flex shrink-0 items-center gap-1 underline-offset-4 hover:underline">
        Open in classic admin
        <ExternalLink className="size-3" aria-hidden />
      </a>
    </div>
  )
}

export function ErrorPage({ href, onRetry }: { href: string; onRetry: () => void }) {
  return (
    <div role="alert" className="flex items-center justify-center p-6 py-10">
      <div className="w-full max-w-md rounded-lg border bg-card p-6">
        <h1 className="text-xl font-semibold">Couldn't load this page</h1>
        <div className="mt-2 flex flex-col items-start gap-4 text-muted-foreground">
          <p>Something went wrong while showing it. Try again, or open it in the classic admin.</p>
          <div className="flex flex-wrap gap-2">
            <Button onClick={onRetry}>Try again</Button>
            <Button variant="outline" asChild>
              <a href={href}>Open in classic admin</a>
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
