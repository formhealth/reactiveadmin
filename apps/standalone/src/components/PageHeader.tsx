export function PageHeader({ title, children }: { title: React.ReactNode; children?: React.ReactNode }) {
  return (
    <header className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
      <h1 className="min-w-0 text-xl font-bold sm:text-2xl [&_button]:text-foreground">{title}</h1>
      {children && <div className="flex items-center gap-2">{children}</div>}
    </header>
  )
}
