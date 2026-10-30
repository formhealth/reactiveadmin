import { ChevronsUpDown, ExternalLink, LogOut } from 'lucide-react'
import { Link } from 'react-router'
import { UiSwitchMenuItem } from '@/components/UiSwitch'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { useMapClassic, useSite } from '@/hooks/useManifest'
import { menuLeaves, menuRoute } from '@/lib/menu'
import { signOut } from '@/lib/session'
import { cn } from '@/lib/utils'

const initialsOf = (name: string) =>
  name
    .split(/[\s@._-]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0])
    .join('')
    .toUpperCase()

function Avatar({ name }: { name: string }) {
  return (
    <span
      aria-hidden
      data-initials={initialsOf(name)}
      className="flex size-7 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary before:content-[attr(data-initials)]"
    />
  )
}

type UserMenuProps = { compact?: boolean; onNavigate?: () => void }

// AA's utility navigation: the signed-in user, its links, and sign out.
export function UserMenu({ compact, onNavigate }: UserMenuProps) {
  const site = useSite()
  const mapUrl = useMapClassic()
  const user = site?.current_user
  if (!site || !user) return null

  // AA lists logout in the utility menu too; it is shown once, as Sign out.
  const leaves = menuLeaves(site.utility_menu).filter((leaf) => !site.logout || leaf.url !== site.logout.url)
  const profile = leaves.find((leaf) => leaf.label === user.display_name)
  const items = leaves.filter((leaf) => leaf !== profile)
  const profileTo = profile && menuRoute(profile, mapUrl)

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" aria-label={`${user.display_name}, account menu`} className={cn(compact ? 'size-8 rounded-full p-0' : 'h-9 min-w-0 flex-1 justify-start gap-2 px-1.5')}>
          <Avatar name={user.display_name} />
          {!compact && (
            <>
              <span className="min-w-0 flex-1 truncate text-left">{user.display_name}</span>
              <ChevronsUpDown className="text-muted-foreground" />
            </>
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent side={compact ? 'bottom' : 'top'} align={compact ? 'end' : 'start'} className="min-w-56">
        {profileTo ? (
          <DropdownMenuItem asChild className="font-semibold">
            <Link to={profileTo} onClick={onNavigate}>
              {user.display_name}
            </Link>
          </DropdownMenuItem>
        ) : (
          <DropdownMenuLabel className="truncate font-semibold text-foreground">{user.display_name}</DropdownMenuLabel>
        )}
        {items.length > 0 && <DropdownMenuSeparator />}
        {items.map((leaf) => {
          const to = menuRoute(leaf, mapUrl)
          return (
            <DropdownMenuItem key={leaf.id} asChild>
              {to ? (
                <Link to={to} onClick={onNavigate}>
                  {leaf.label}
                </Link>
              ) : (
                <a href={leaf.url ?? undefined} target="_blank" rel="noopener noreferrer">
                  {leaf.label}
                  <ExternalLink className="ml-auto" />
                </a>
              )}
            </DropdownMenuItem>
          )
        })}
        <UiSwitchMenuItem />
        {site.logout && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={() => signOut(site.logout!)}>
              <LogOut />
              Sign out
            </DropdownMenuItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
