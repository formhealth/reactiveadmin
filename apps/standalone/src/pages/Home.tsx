import { Navigate } from 'react-router'
import { ErrorState } from '@/components/ErrorState'
import { PageHeader } from '@/components/PageHeader'
import { UiSwitchPanel } from '@/components/UiSwitch'
import { useDocumentTitle, useManifest, useMapClassic } from '@/hooks/useManifest'
import { modKey } from '@/lib/platform'

// AA's `root_to`: a resource or a classic URL that maps to a screen. Anything else gets the welcome page.
export function Home() {
  const { data, error } = useManifest()
  const mapUrl = useMapClassic()
  useDocumentTitle()

  const home = data?.site.home
  const to = home?.resource ? `/${home.resource}` : home?.url ? mapUrl(home.url) : undefined
  if (to && to !== '/') return <Navigate to={to} replace />

  return error ? (
    <ErrorState error={error} label="the admin" />
  ) : (
    <div className="flex flex-col gap-2">
      <PageHeader title="Welcome" />
      <p className="text-muted-foreground">
        Pick a page from the menu, or press <kbd className="rounded-sm border px-1.5 font-mono text-xs">{modKey}K</kbd> to jump to any page.
      </p>
      <UiSwitchPanel />
    </div>
  )
}
