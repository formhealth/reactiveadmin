import { useEffect, useMemo } from 'react'
import { useQueries } from '@tanstack/react-query'
import { ExternalLink, LayoutList } from 'lucide-react'
import { useNavigate } from 'react-router'
import { ApiError } from '@/api/fetcher'
import type { MenuItem } from '@/api/generated/model'
import { Command, CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command'
import { Skeleton } from '@/components/ui/skeleton'
import { useManifest, useMapClassic } from '@/hooks/useManifest'
import { fullPath, groupRoute, menuGroups, menuLeaves, menuRoute, type MenuLeaf } from '@/lib/menu'
import { forgetVisit, readRecents } from '@/lib/recent'
import { labelGroups, labelQueryOptions, labelsByKey } from '@/lib/recentLabels'

type CommandPaletteProps = { items: MenuItem[]; open: boolean; onOpenChange: (open: boolean) => void }

const SHOWN_RECENTS = 5
const missing = (error: unknown) => error instanceof ApiError && (error.status === 403 || error.status === 404)

// Visits are stored as pointers; names come from one small display-name lookup per resource, never the records.
function RecentRecords({ go }: { go: (to: string) => void }) {
  const { data } = useManifest()
  const recents = useMemo(() => readRecents().slice(0, SHOWN_RECENTS), [])
  const groups = useMemo(() => labelGroups(recents), [recents])
  const results = useQueries({ queries: groups.map(labelQueryOptions) })
  const names = labelsByKey(results.map((result) => result.data))
  // The lookup answers only for records the user may still read, so a settled answer without one means it is gone.
  const gone = (recent: (typeof recents)[number]) => {
    const result = results[groups.findIndex((group) => group.resource === recent.resource)]
    return missing(result.error) || (result.isSuccess && !names.has(`${recent.resource}/${recent.id}`))
  }

  useEffect(() => {
    recents.filter(gone).forEach(forgetVisit)
  }, [results, recents]) // eslint-disable-line react-hooks/exhaustive-deps -- `gone` derives from `results`

  const shown = recents.filter((recent) => !gone(recent))
  if (shown.length === 0) return null

  return (
    <CommandGroup heading="Recent records">
      {shown.map((recent) => {
        const name = names.get(`${recent.resource}/${recent.id}`)
        const label = data?.resources.find((r) => r.key === recent.resource)?.label ?? recent.resource
        return name ? (
          <CommandItem key={`${recent.resource}/${recent.id}`} value={`${label} ${name} ${recent.id}`} onSelect={() => go(`/${recent.resource}/${recent.id}`)}>
            <span>
              <span className="text-muted-foreground">{label} / </span>
              {name}
            </span>
          </CommandItem>
        ) : (
          <div key={`${recent.resource}/${recent.id}`} aria-hidden className="flex h-8 items-center px-2">
            <Skeleton className="h-4 w-48" />
          </div>
        )
      })}
    </CommandGroup>
  )
}

export function CommandPalette({ items, open, onOpenChange }: CommandPaletteProps) {
  const navigate = useNavigate()
  const mapUrl = useMapClassic()
  const leaves = useMemo(() => menuLeaves(items), [items])
  const groups = useMemo(() => menuGroups(items), [items])

  const go = (to: string | undefined, url?: string | null) => {
    onOpenChange(false)
    if (to) navigate(to)
    else window.open(url ?? '', '_blank', 'noopener,noreferrer')
  }
  const goLeaf = (leaf: MenuLeaf) => go(menuRoute(leaf, mapUrl), leaf.url)

  return (
    <CommandDialog open={open} onOpenChange={onOpenChange} title="Go to a page" description="Search every page in the menu">
      <Command>
        <CommandInput placeholder="Go to a page or recent record" />
        <CommandList>
          <CommandEmpty>No pages match.</CommandEmpty>
          <RecentRecords go={go} />
          <CommandGroup heading="Pages">
            {leaves.map((leaf) => {
              const external = !menuRoute(leaf, mapUrl)
              return (
                <CommandItem key={leaf.id} value={`${fullPath(leaf)} ${leaf.description ?? ''}`} onSelect={() => goLeaf(leaf)}>
                  <span>
                    {leaf.path.length > 0 && <span className="text-muted-foreground">{leaf.path.join(' / ')} / </span>}
                    {leaf.label}
                  </span>
                  {external && <ExternalLink aria-label="Opens in a new tab" className="size-3.5 text-muted-foreground" />}
                </CommandItem>
              )
            })}
          </CommandGroup>
          {groups.length > 0 && (
            <CommandGroup heading="Sections">
              {groups.map((group) => (
                <CommandItem key={group.id} value={`${fullPath(group)} overview ${group.description ?? ''}`} onSelect={() => go(groupRoute(group.id))}>
                  <span>
                    {group.path.length > 0 && <span className="text-muted-foreground">{group.path.join(' / ')} / </span>}
                    {group.label}
                  </span>
                  <LayoutList aria-label="Section overview" className="size-3.5 text-muted-foreground" />
                </CommandItem>
              ))}
            </CommandGroup>
          )}
        </CommandList>
      </Command>
    </CommandDialog>
  )
}
