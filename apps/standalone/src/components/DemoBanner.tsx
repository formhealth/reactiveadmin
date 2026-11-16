export const isDemo = import.meta.env.VITE_DEMO === '1'

export function DemoBanner() {
  return (
    <div role="note" className="border-b bg-muted px-4 py-1.5 text-center text-sm text-muted-foreground">
      Demo with sample data. Saves are simulated and nothing is stored.{' '}
      <a href="/reactiveadmin/" className="font-medium text-foreground underline underline-offset-2">
        Back to the site
      </a>
    </div>
  )
}
