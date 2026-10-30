import { Fragment } from 'react'
import { ExternalLink, MoreHorizontal } from 'lucide-react'
import { Link } from 'react-router'
import type { Action } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { ClassicLink as ApiDeniedLink } from '@/components/ApiDenied'
import { useMapClassic } from '@/hooks/useManifest'
import { useIsWide } from '@/hooks/useMediaQuery'
import { useRecordAction, type ActionContext } from '@/hooks/useRecordAction'
import { withClassic } from '@/lib/classic'
import { cn } from '@/lib/utils'

// `download` marks links that stream a file (the CSV export) rather than navigate.
export type BarAction = Action & { download?: boolean }

type RunProps = { action: BarAction; run: (action: Action) => void; editTo?: string; size?: 'default' | 'sm' }

const editClass = 'border-primary text-primary hover:bg-primary/10 hover:text-primary'

// A plain GET to a classic URL: no API call, confirm or view in between.
const isLink = (a: BarAction) => (a.method ?? 'get') === 'get' && !a.confirm && !!a.href && !a.view && !a.form_path && (a.kind === 'link' || !a.api_path)

function useLinkTarget(action: BarAction) {
  const mapUrl = useMapClassic()
  if (!isLink(action)) return undefined
  const to = action.external || action.download ? undefined : mapUrl(action.href!)
  return { to, href: action.href!, external: action.external }
}

const ClassicLink = ({ action }: { action: BarAction }) =>
  action.href ? (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button asChild variant="ghost" size="icon-sm">
          <a href={withClassic(action.href)} aria-label={`Open ${action.label} in classic admin`}>
            <ExternalLink />
          </a>
        </Button>
      </TooltipTrigger>
      <TooltipContent>Open in classic admin</TooltipContent>
    </Tooltip>
  ) : null

function DisabledButton({ action, reason, size, className }: { action: BarAction; reason: string; size?: RunProps['size']; className?: string }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          variant={action.kind === 'edit' ? 'outline' : 'secondary'}
          size={size}
          aria-disabled
          onClick={(e) => e.preventDefault()}
          className={cn(className, 'cursor-not-allowed opacity-60 hover:bg-transparent')}
        >
          {action.label}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{reason}</TooltipContent>
    </Tooltip>
  )
}

// What the host reserved for the classic admin is never a button: the server refuses it, so it is a link out.
const reservedReason = (action: BarAction) => action.disabled_reason ?? 'Only available in the classic admin'

function ApiDeniedButton({ action, size, className }: { action: BarAction; size?: RunProps['size']; className?: string }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button asChild variant={action.kind === 'edit' ? 'outline' : 'secondary'} size={size} className={className}>
          <ApiDeniedLink href={action.classic_url!}>{action.label}</ApiDeniedLink>
        </Button>
      </TooltipTrigger>
      <TooltipContent>{reservedReason(action)}</TooltipContent>
    </Tooltip>
  )
}

export function ActionButton({ action, run, editTo, size }: RunProps) {
  const link = useLinkTarget(action)
  const variant = action.kind === 'edit' ? 'outline' : 'secondary'
  const className = action.kind === 'edit' ? editClass : undefined

  if (action.api_denied && action.classic_url) return <ApiDeniedButton action={action} size={size} className={className} />

  if (action.supported === false)
    return (
      <span className="inline-flex items-center gap-0.5">
        <DisabledButton action={action} size={size} reason={action.disabled_reason ?? "This can't run from here yet"} />
        <ClassicLink action={action} />
      </span>
    )
  if (!action.enabled) return <DisabledButton action={action} size={size} reason={action.disabled_reason ?? 'Not available'} className={className} />

  if (action.kind === 'edit' && editTo)
    return (
      <Button asChild variant={variant} size={size} className={className}>
        <Link to={editTo}>{action.label}</Link>
      </Button>
    )

  if (link)
    return (
      <Button asChild variant={variant} size={size} className={className}>
        {link.to ? (
          <Link to={link.to}>{action.label}</Link>
        ) : (
          <a href={link.href} download={action.download || undefined} {...(link.external && { target: '_blank', rel: 'noopener noreferrer' })}>
            {action.label}
            {link.external && <ExternalLink />}
          </a>
        )}
      </Button>
    )

  return (
    <Button variant={variant} size={size} className={className} onClick={() => run(action)}>
      {action.label}
      {action.external && <ExternalLink />}
    </Button>
  )
}

export function ActionMenuItem({ action, run }: Omit<RunProps, 'editTo' | 'size'>) {
  const link = useLinkTarget(action)
  const danger = action.kind === 'destroy' ? 'destructive' : 'default'

  if (action.api_denied && action.classic_url)
    return (
      <DropdownMenuItem asChild variant={danger}>
        <ApiDeniedLink href={action.classic_url}>
          <span className="flex flex-col">
            {action.label}
            <span className="text-xs font-normal text-muted-foreground">{reservedReason(action)}</span>
          </span>
        </ApiDeniedLink>
      </DropdownMenuItem>
    )

  if (action.supported === false)
    return (
      <>
        <DropdownMenuItem disabled className="flex-col items-start gap-0">
          {action.label}
          <span className="text-xs text-muted-foreground">{action.disabled_reason ?? "This can't run from here yet"}</span>
        </DropdownMenuItem>
        {action.href && (
          <DropdownMenuItem asChild>
            <a href={withClassic(action.href)}>
              Open in classic admin
              <ExternalLink className="ml-auto" />
            </a>
          </DropdownMenuItem>
        )}
      </>
    )

  if (action.enabled && link)
    return (
      <DropdownMenuItem asChild>
        {link.to ? (
          <Link to={link.to}>{action.label}</Link>
        ) : (
          <a href={link.href} download={action.download || undefined} {...(link.external && { target: '_blank', rel: 'noopener noreferrer' })}>
            {action.label}
            {link.external && <ExternalLink className="ml-auto" />}
          </a>
        )}
      </DropdownMenuItem>
    )

  return (
    <DropdownMenuItem disabled={!action.enabled} variant={danger} onSelect={() => run(action)} className="flex-col items-start gap-0">
      {action.label}
      {!action.enabled && action.disabled_reason && <span className="text-xs text-muted-foreground">{action.disabled_reason}</span>}
    </DropdownMenuItem>
  )
}

type ActionBarProps = {
  actions: BarAction[]
  ctx?: ActionContext
  // The page's primary button (e.g. New), kept last and always visible.
  lead?: React.ReactNode
}

// Header actions: buttons from `sm` up, folded into a "more" menu below it. Destructive actions always live in the menu.
export function ActionBar({ actions, ctx = {}, lead }: ActionBarProps) {
  const { request, dialogs } = useRecordAction(ctx)
  const wide = useIsWide()
  const safe = actions.filter((a) => a.kind !== 'destroy')
  const overflow = [...(wide ? [] : safe), ...actions.filter((a) => a.kind === 'destroy')]
  const editTo = ctx.resource && ctx.id ? `/${ctx.resource}/${ctx.id}/edit` : undefined

  return (
    <div className="flex flex-wrap items-center gap-2">
      {wide && safe.map((action) => <ActionButton key={action.key} action={action} run={request} editTo={editTo} />)}
      {overflow.length > 0 && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="outline" size="icon" aria-label="More actions">
              <MoreHorizontal />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-52">
            {overflow.map((action, i) => (
              <Fragment key={action.key}>
                {action.kind === 'destroy' && i > 0 && overflow[i - 1].kind !== 'destroy' && <DropdownMenuSeparator />}
                <ActionMenuItem action={action} run={request} />
              </Fragment>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      )}
      {lead}
      {dialogs}
    </div>
  )
}
