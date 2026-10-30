import { ExternalLink } from 'lucide-react'
import { Link } from 'react-router'
import { formatDistanceToNow } from 'date-fns'
import { IdTip, IdValue } from '@/components/IdValue'
import { Badge } from '@/components/ui/badge'
import { useFormats, useMapClassic } from '@/hooks/useManifest'
import { formatDay, formatMoment, parseDay, parseMoment } from '@/lib/datetime'
import { isUuid, shortId } from '@/lib/ids'
import { safeHref } from '@/lib/safeUrl'
import { cn } from '@/lib/utils'
import type { NodeVariant, Ref as RefData } from '@/api/generated/model'
import { useIdMode } from './context'
import type { NodeProps } from './Node'

const refPath = ({ resource, id }: RefData) => `/${resource}/${id}`
const linkClass = 'underline decoration-muted-foreground/50 underline-offset-4 hover:decoration-foreground'

export const Empty = () => <span className="text-muted-foreground">—</span>

export const Text = ({ node }: NodeProps) => {
  const text = node.text ?? node.label ?? String(node.value ?? '')
  const mode = useIdMode()
  return isUuid(text) ? <IdValue value={text} full={mode === 'full'} /> : <span>{text}</span>
}

// UUID labels render short and mono; the tooltip carries the full value and a copy button.
const labelProps = (label?: string | null) => (isUuid(label) ? { label: `${shortId(label)}…`, className: 'font-mono', 'aria-label': label } : { label })

function WithIdTip({ id, children }: { id?: string | null; children: React.ReactElement }) {
  return isUuid(id) ? <IdTip value={id}>{children}</IdTip> : children
}

export const NumberNode = ({ node }: NodeProps) => {
  const n = Number(node.value)
  return <span className="tabular-nums">{Number.isNaN(n) ? String(node.value) : n.toLocaleString()}</span>
}

export const BooleanNode = ({ node }: NodeProps) =>
  node.value ? <Badge className={variantClass.success}>Yes</Badge> : <Badge variant="secondary">No</Badge>

export const DateNode = ({ node }: NodeProps) => {
  const formats = useFormats()
  const date = parseDay(node.value)
  if (!date) return <Empty />
  return (
    <time dateTime={String(node.value)} title={String(node.value)} className="whitespace-nowrap">
      {formatDay(date, formats)}
    </time>
  )
}

export const DateTimeNode = ({ node }: NodeProps) => {
  const formats = useFormats()
  const date = parseMoment(node.value)
  if (!date) return <Empty />
  return (
    <time dateTime={String(node.value)} title={String(node.value)} className="whitespace-nowrap">
      {formatMoment(date, formats)}{' '}
      <span data-relative className="text-xs text-muted-foreground">{formatDistanceToNow(date, { addSuffix: true })}</span>
    </time>
  )
}

export const Ref = ({ node }: NodeProps) => {
  const { label, ...extra } = labelProps(node.label)
  return node.ref ? (
    <WithIdTip id={node.label}>
      <Link to={refPath(node.ref)} {...extra} className={cn(linkClass, extra.className)}>
        {label}
      </Link>
    </WithIdTip>
  ) : (
    <span>{node.label}</span>
  )
}

export const LinkNode = ({ node }: NodeProps) => {
  const mapUrl = useMapClassic()
  if (node.ref) return <Ref node={node} />
  const { label, ...extra } = labelProps(node.label)
  const href = safeHref(node.href, node.external)
  if (!href) return <span>{label}</span>
  const className = cn(linkClass, extra.className, node.external && 'inline-flex items-center gap-1 whitespace-nowrap')
  const to = !node.external ? mapUrl(href) : undefined
  return (
    <WithIdTip id={node.label}>
      {to ? (
        <Link to={to} {...extra} className={className}>
          {label}
        </Link>
      ) : (
        <a href={href} {...extra} {...(node.external && { target: '_blank', rel: 'noopener noreferrer' })} className={className}>
          {label}
          {node.external && <ExternalLink className="size-3 shrink-0" aria-hidden />}
        </a>
      )}
    </WithIdTip>
  )
}

const variantClass: Record<NodeVariant, string> = {
  success: 'bg-success-soft text-success',
  warning: 'bg-warning-soft text-warning',
  danger: 'bg-danger-soft text-danger',
  info: 'bg-info-soft text-info',
  neutral: '',
}

export const Status = ({ node }: NodeProps) => (
  <Badge variant="secondary" className={variantClass[node.variant ?? 'neutral']}>
    {node.label}
  </Badge>
)
