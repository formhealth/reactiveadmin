import { useState } from 'react'
import { Moon, PanelLeftClose, Search, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
import type { MenuItem } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { modKey } from '@/lib/platform'
import { Brand } from './Brand'
import { MenuTree } from './MenuTree'
import { UserMenu } from './UserMenu'

function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme()
  return (
    <Button variant="ghost" size="icon" aria-label="Toggle dark mode" onClick={() => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')}>
      <Sun className="hidden size-4 dark:block" />
      <Moon className="size-4 dark:hidden" />
    </Button>
  )
}

type SidebarProps = {
  items?: MenuItem[]
  failed?: boolean
  onRetry?: () => void
  onNavigate?: () => void
  onOpenPalette: () => void
  onCollapse?: () => void
}

export function Sidebar({ items, failed, onRetry, onNavigate, onOpenPalette, onCollapse }: SidebarProps) {
  const [term, setTerm] = useState('')

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex h-12 shrink-0 items-center px-4">
        <Brand onNavigate={onNavigate} />
      </div>

      <div className="flex shrink-0 items-center gap-2 px-3 pb-3">
        <div className="relative flex-1">
          <Search aria-hidden className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="search"
            value={term}
            onChange={(e) => setTerm(e.target.value)}
            onKeyDown={(e) => e.key === 'Escape' && setTerm('')}
            placeholder="Filter menu"
            aria-label="Filter menu"
            className="h-9 w-full rounded-md border border-input bg-background pr-2 pl-8 text-sm outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/50"
          />
        </div>
        <button
          type="button"
          onClick={onOpenPalette}
          aria-label={`Open command palette ${modKey}K`}
          className="hidden h-9 shrink-0 items-center rounded-md border border-input px-2 font-mono text-xs text-muted-foreground outline-none hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring lg:flex"
        >
          {modKey}K
        </button>
      </div>

      <nav aria-label="Main" className="min-h-0 flex-1 overflow-y-auto pb-4">
        {failed ? (
          <div className="flex flex-col items-start gap-2 px-4 text-sm text-muted-foreground">
            Couldn't load the menu.
            <Button variant="outline" size="sm" onClick={onRetry}>
              Retry
            </Button>
          </div>
        ) : items ? (
          <MenuTree items={items} term={term} onNavigate={onNavigate} />
        ) : (
          <div className="flex flex-col gap-3 px-4" aria-hidden>
            {[40, 56, 48, 52, 36].map((w, i) => (
              <Skeleton key={i} className="h-4" style={{ width: `${w}%` }} />
            ))}
          </div>
        )}
      </nav>

      <div className="flex shrink-0 items-center gap-1 border-t px-2 py-2">
        <div className="flex min-w-0 flex-1">
          <UserMenu onNavigate={onNavigate} />
        </div>
        <ThemeToggle />
        {onCollapse && (
          <Button variant="ghost" size="icon" onClick={onCollapse} aria-label="Collapse menu">
            <PanelLeftClose />
          </Button>
        )}
      </div>
    </div>
  )
}
