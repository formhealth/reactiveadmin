import { createContext, useContext, type CSSProperties } from 'react'
import type { Action, Node as NodeData, NodeLayout } from '@/api/generated/model'
import { ActionButton } from '@/components/ActionBar'
import { useRecordAction } from '@/hooks/useRecordAction'
import { cn } from '@/lib/utils'
import { useNodeContext } from './context'
import { Empty } from './scalars'
import { NodeList, type NodeProps } from './Node'
import { emphasisOf, MAX_WIDTH, spacingOf } from './style'

type Breakpoint = NonNullable<NodeLayout['breakpoint']>

// What a child needs to know about the row or grid it sits in. Tailwind only emits classes it can read in the source,
// so every breakpoint variant is spelled out here and sizes travel as CSS variables.
type Flow = { display: NodeLayout['display']; breakpoint?: Breakpoint | null }
const FlowContext = createContext<Flow | undefined>(undefined)

const ROW: Record<Breakpoint, string> = { sm: 'sm:flex-row', md: 'md:flex-row', lg: 'lg:flex-row', xl: 'xl:flex-row' }
const COLUMNS: Record<Breakpoint, string> = { sm: 'sm:grid-cols-(--cols)', md: 'md:grid-cols-(--cols)', lg: 'lg:grid-cols-(--cols)', xl: 'xl:grid-cols-(--cols)' }
const WIDTH: Record<Breakpoint, string> = { sm: 'sm:w-(--width)', md: 'md:w-(--width)', lg: 'lg:w-(--width)', xl: 'xl:w-(--width)' }
const SPAN: Record<Breakpoint, string> = { sm: 'sm:col-span-(--span)', md: 'md:col-span-(--span)', lg: 'lg:col-span-(--span)', xl: 'xl:col-span-(--span)' }
const ALIGN = { start: 'items-start', center: 'items-center', end: 'items-end', stretch: 'items-stretch', baseline: 'items-baseline' }
const JUSTIFY = { start: 'justify-start', center: 'justify-center', end: 'justify-end', between: 'justify-between' }
const TEXT = { left: 'text-left', center: 'text-center', right: 'text-right' }
const SHARE = { '1/4': '25%', '1/3': '33.333%', '1/2': '50%', '2/3': '66.667%', '3/4': '75%', full: '100%' }

const grid = (n = 1) => `repeat(${n}, minmax(0, 1fr))`

function layoutOf(layout: NodeLayout) {
  const { display, breakpoint, direction = 'row', gap = 0 } = layout
  const style = { '--gap': `calc(var(--spacing) * ${gap})` } as CSSProperties & Record<string, string>
  if (display === 'grid') {
    Object.assign(style, { '--base-cols': grid(layout.base_columns), '--cols': grid(layout.columns) })
    return { style, className: cn('grid grid-cols-(--base-cols) gap-(--gap)', breakpoint && COLUMNS[breakpoint], !breakpoint && 'grid-cols-(--cols)') }
  }
  const row = direction === 'row'
  return {
    style,
    className: cn(
      'flex gap-(--gap)',
      row ? (breakpoint ? ['flex-col', ROW[breakpoint]] : 'flex-row') : 'flex-col',
      layout.wrap && 'flex-wrap',
      layout.align && ALIGN[layout.align],
      layout.justify && JUSTIFY[layout.justify],
    ),
  }
}

// A div with layout hints: a row from its breakpoint up (stacked below), a grid, or a plain stack.
export function Box({ node }: NodeProps) {
  const parent = useContext(FlowContext)
  const own = node.layout ? layoutOf(node.layout) : undefined
  const margin = spacingOf(node.spacing)
  const style = { ...own?.style, ...margin.style } as CSSProperties & Record<string, string>
  const placement: string[] = []

  if (parent?.display === 'flex' && node.width) {
    style['--width'] = SHARE[node.width]
    placement.push('w-full', parent.breakpoint ? WIDTH[parent.breakpoint] : 'w-(--width)')
  }
  if (parent?.display === 'grid' && node.span) {
    style['--span'] = String(node.span)
    placement.push(parent.breakpoint ? SPAN[parent.breakpoint] : 'col-span-(--span)')
  }

  return (
    <div
      data-tag={node.tag}
      style={style}
      className={cn(
        'min-w-0',
        own?.className ?? 'flex flex-col gap-4 [&>[data-slot=card]:only-child]:flex-1',
        placement,
        node.text_align && TEXT[node.text_align],
        margin.className,
        node.max_width && MAX_WIDTH[node.max_width],
        node.grow && parent?.display === 'flex' && 'grow',
        emphasisOf(node),
      )}
    >
      <FlowContext value={node.layout ? { display: node.layout.display, breakpoint: node.layout.breakpoint } : undefined}>
        <NodeList nodes={node.children} />
      </FlowContext>
    </div>
  )
}

const LINK: Pick<Action, 'kind' | 'method' | 'enabled'> = { kind: 'link', method: 'get', enabled: true }

const toAction = (child: NodeData, index: number): Action | undefined =>
  child.type === 'action'
    ? child.action
    : child.type === 'link' && child.href
      ? { ...LINK, key: `link-${index}`, label: child.label ?? child.href, href: child.href, external: child.external }
      : undefined

const JUSTIFY_TOOLBAR = { start: 'justify-start', center: 'justify-center', end: 'justify-end' }

// Buttons and links that sit together. One shared action runner, so the confirm and result handling are the same as
// everywhere else.
export function Toolbar({ node }: NodeProps) {
  const { request, dialogs } = useRecordAction(useNodeContext())
  const actions = (node.children ?? []).flatMap((child, i) => toAction(child, i) ?? [])
  if (actions.length === 0) return null
  const margin = spacingOf(node.spacing)
  return (
    <div role="toolbar" style={margin.style} className={cn('flex flex-wrap items-center gap-2', JUSTIFY_TOOLBAR[node.align ?? 'start'], margin.className)}>
      {actions.map((action, i) => (
        // The same action can sit twice with different params (Refresh and Rebuild), so its key alone repeats.
        <ActionButton key={`${i}-${action.key}`} action={action} run={request} size="sm" />
      ))}
      {dialogs}
    </div>
  )
}

export const List = ({ node }: NodeProps) => {
  const Tag = node.ordered ? 'ol' : 'ul'
  return (
    <Tag className={cn('flex flex-col gap-1 pl-5', node.ordered ? 'list-decimal' : 'list-disc')}>
      <NodeList nodes={node.children} />
    </Tag>
  )
}

export const ListItem = ({ node }: NodeProps) => (
  // A nested list's links sit a line below their parent's, so the gap keeps link targets 24px apart (WCAG 2.5.8).
  <li className="pl-1 [&>:is(ul,ol)]:mt-1">
    <NodeList nodes={node.children} />
  </li>
)

export { Masked } from '@/components/Masked'

// A node type this client doesn't know (the server is newer): show what it carries rather than nothing or a crash.
export function Unknown({ node }: NodeProps) {
  if (node.children?.length)
    return (
      <div className="flex flex-col gap-2">
        <NodeList nodes={node.children} />
      </div>
    )
  const text = node.text ?? node.label ?? (node.value == null ? undefined : String(node.value))
  return text ? <span>{text}</span> : <Empty />
}
