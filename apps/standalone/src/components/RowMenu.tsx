import { MoreHorizontal } from 'lucide-react'
import { Link, useLocation } from 'react-router'
import type { Row } from '@/api/generated/model'
import { ActionMenuItem } from '@/components/ActionBar'
import { ClassicLink } from '@/components/ApiDenied'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { useResourceSummary } from '@/hooks/useManifest'
import { useRecordAction } from '@/hooks/useRecordAction'
import { classicPage, isDenied } from '@/lib/apiDenied'
import { hasRowActions } from '@/lib/permissions'

type RowMenuProps = { resource: string; row: Row; className?: string; defaults?: boolean }

export function RowMenu({ resource, row, className, defaults = true }: RowMenuProps) {
  const { search } = useLocation()
  const { request, dialogs } = useRecordAction({ resource, id: row.id, name: row.display_name })
  const { summary } = useResourceSummary(resource)
  const show = defaults && row.permissions.show
  const update = defaults && row.permissions.update
  // A page the API refuses is a link to the classic admin, or nothing when it has no classic page to point at.
  const entry = (action: 'show' | 'edit', label: string, to: string, state?: object) => {
    const href = classicPage(summary, action, action === 'edit' ? `/${row.id}/edit` : `/${row.id}`)
    if (isDenied(summary, action) && !href) return null
    return (
      <DropdownMenuItem asChild>
        {href ? (
          <ClassicLink href={href}>{label}</ClassicLink>
        ) : (
          <Link to={to} state={state}>
            {label}
          </Link>
        )}
      </DropdownMenuItem>
    )
  }
  const custom = row.actions ?? []
  if (!hasRowActions(row, defaults)) return null
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon-sm" aria-label={`Actions for ${row.display_name ?? `record ${row.id}`}`} className={className}>
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="min-w-48">
          {show && entry('show', 'View', `/${resource}/${row.id}`, { search })}
          {update && entry('edit', 'Edit', `/${resource}/${row.id}/edit`)}
          {custom.length > 0 && (show || update) && <DropdownMenuSeparator />}
          {custom.map((action) => (
            <ActionMenuItem key={action.key} action={action} run={request} />
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
      {dialogs}
    </>
  )
}
