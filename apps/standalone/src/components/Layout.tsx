import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Menu, PanelLeftOpen } from 'lucide-react'
import { Outlet, useLocation } from 'react-router'
import { ApiError } from '@/api/fetcher'
import { getGetManifestQueryKey } from '@/api/generated/core'
import { SignInRequired } from '@/components/ErrorState'
import { Brand } from '@/components/menu/Brand'
import { LazyCommandPalette, LazyMobileMenu } from '@/components/menu/lazy'
import { Sidebar } from '@/components/menu/Sidebar'
import { UserMenu } from '@/components/menu/UserMenu'
import { Button } from '@/components/ui/button'
import { useIsDesktop } from '@/hooks/useMediaQuery'
import { useManifest } from '@/hooks/useManifest'
import { useStoredState } from '@/hooks/useStoredState'
import { hosted } from '@/lib/base'
import { goClassic, lacksScreen } from '@/lib/boot'
import { isLanding } from '@/lib/landing'
import { clearManifest, saveManifest, SCHEMA_VERSION } from '@/lib/manifestCache'

function Notice({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div role="alert" className="flex min-h-screen items-center justify-center p-6">
      <div className="w-full max-w-md rounded-lg border bg-card p-6">
        <h1 className="text-xl font-semibold">{title}</h1>
        <div className="mt-2 flex flex-col items-start gap-4 text-muted-foreground">{children}</div>
      </div>
    </div>
  )
}

export function Layout() {
  const { data, error, refetch, isFetched } = useManifest()
  const { pathname, key } = useLocation()
  const queryClient = useQueryClient()
  const desktop = useIsDesktop()
  const [railOpen, setRailOpen] = useStoredState('ra:rail', true)
  const [sheetOpen, setSheetOpen] = useState(false)
  const [paletteOpen, setPaletteOpen] = useState(false)
  const unauthorized = error instanceof ApiError && error.status === 401
  const favicon = data?.site.favicon

  // A persisted manifest paints first (it has no fetch time); this swaps in the live one once per load.
  useEffect(() => {
    const key = getGetManifestQueryKey()
    if (queryClient.getQueryData(key) && queryClient.getQueryState(key)?.dataUpdatedAt === 0) queryClient.invalidateQueries({ queryKey: key })
  }, [queryClient])

  useEffect(() => {
    if (data) saveManifest(data)
  }, [data])

  // The server hands this page to every browser that chose the new admin, whatever the URL. If it has no screen for the
  // one it landed on, classic does.
  useEffect(() => {
    if (hosted && isFetched && data && isLanding(key) && lacksScreen(pathname, data)) goClassic()
  }, [isFetched, data, key, pathname])

  useEffect(() => {
    if (unauthorized) clearManifest()
  }, [unauthorized])

  useEffect(() => {
    if (!favicon) return
    const link = document.querySelector<HTMLLinkElement>('link[rel~="icon"]') ?? document.head.appendChild(Object.assign(document.createElement('link'), { rel: 'icon' }))
    link.href = favicon
  }, [favicon])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setPaletteOpen((open) => !open)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  if (unauthorized) return <SignInRequired fullPage />
  if (data && data.schema_version !== SCHEMA_VERSION)
    return (
      <Notice title="Admin updated">
        <p>The server was updated since this page loaded. Reload to continue.</p>
        <Button onClick={() => window.location.reload()}>Reload</Button>
      </Notice>
    )

  const sidebar = (extra: { onNavigate?: () => void; onCollapse?: () => void }) => (
    <Sidebar
      items={data?.menu}
      failed={!!error && !data}
      onRetry={() => refetch()}
      onOpenPalette={() => {
        setSheetOpen(false)
        setPaletteOpen(true)
      }}
      {...extra}
    />
  )
  const showRail = desktop && railOpen

  return (
    <div className="flex min-h-screen">
      {showRail && (
        <aside className="sticky top-0 h-screen w-72 shrink-0 border-r bg-sidebar text-sidebar-foreground">
          {sidebar({ onCollapse: () => setRailOpen(false) })}
        </aside>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        {!showRail && (
          <div className="sticky top-0 z-30 flex h-12 shrink-0 items-center gap-2 border-b bg-background px-3">
            <Button variant="ghost" size="icon" aria-label="Open menu" onClick={() => (desktop ? setRailOpen(true) : setSheetOpen(true))}>
              {desktop ? <PanelLeftOpen /> : <Menu />}
            </Button>
            <Brand />
            <div className="ml-auto">
              <UserMenu compact />
            </div>
          </div>
        )}
        <main className="mx-auto w-full max-w-[1600px] flex-1 px-4 py-5 sm:px-6">
          <Outlet />
        </main>
      </div>

      <LazyMobileMenu open={sheetOpen && !desktop} onOpenChange={setSheetOpen}>
        {sidebar({ onNavigate: () => setSheetOpen(false) })}
      </LazyMobileMenu>

      <LazyCommandPalette items={data?.menu ?? []} open={paletteOpen} onOpenChange={setPaletteOpen} />
    </div>
  )
}
