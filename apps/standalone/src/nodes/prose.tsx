import { createElement, type ReactNode } from 'react'
import { ChevronRight } from 'lucide-react'
import type { NodeMarksItem } from '@/api/generated/model'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import { Separator } from '@/components/ui/separator'
import { cn } from '@/lib/utils'
import { NodeList, type NodeProps } from './Node'
import { Text } from './scalars'
import { TONE } from './style'

const MARK: Record<NodeMarksItem, (children: ReactNode) => ReactNode> = {
  strong: (c) => <strong className="font-semibold">{c}</strong>,
  em: (c) => <em>{c}</em>,
  code: (c) => <code className="rounded-sm bg-muted px-1 py-0.5 font-mono text-[0.85em]">{c}</code>,
  underline: (c) => <u className="underline-offset-2">{c}</u>,
  strike: (c) => <s>{c}</s>,
  mark: (c) => <mark className="rounded-sm bg-warning-soft px-0.5 text-foreground">{c}</mark>,
  small: (c) => <small className="text-xs">{c}</small>,
  sub: (c) => <sub>{c}</sub>,
  sup: (c) => <sup>{c}</sup>,
}

// Text keeps its plain look unless the server marked it; marks nest in the order given, outermost first.
export function RichText({ node }: NodeProps) {
  const wrap = cn(node.tone && TONE[node.tone], node.nowrap && 'whitespace-nowrap')
  if (!node.marks?.length && !node.title && !wrap) return <Text node={node} />
  const inner = (node.marks ?? []).reduceRight<ReactNode>((children, mark) => MARK[mark]?.(children) ?? children, node.text ?? '')
  const marked = node.title ? (
    <abbr title={node.title} className="cursor-help underline decoration-dotted underline-offset-4">
      {inner}
    </abbr>
  ) : (
    inner
  )
  return wrap ? <span className={wrap}>{marked}</span> : marked
}

// A div with the paragraph role: actions and other block content can sit inline with the text without invalid nesting.
export const Paragraph = ({ node }: NodeProps) => (
  <div role="paragraph" className="min-w-0 leading-relaxed break-words">
    <NodeList nodes={node.children} />
  </div>
)

export const Break = () => <br />

const HEADING = [
  'text-xl font-semibold',
  'text-lg font-semibold',
  'text-base font-semibold',
  'text-sm font-semibold',
  'text-sm font-medium',
  'text-xs font-medium tracking-wide text-muted-foreground uppercase',
]

export function Heading({ node }: NodeProps) {
  const level = Math.min(Math.max(node.level ?? 3, 1), 6)
  return createElement(`h${level}`, { className: cn('min-w-0 leading-snug break-words', HEADING[level - 1]) }, <NodeList nodes={node.children} />)
}

export const Divider = () => <Separator className="my-1" decorative={false} />

export const Blockquote = ({ node }: NodeProps) => (
  <blockquote className="flex flex-col gap-2 border-l-2 pl-3 text-muted-foreground">
    <NodeList nodes={node.children} />
  </blockquote>
)

export function Disclosure({ node }: NodeProps) {
  return (
    <Collapsible defaultOpen={node.open} className="group/disclosure rounded-md border">
      <CollapsibleTrigger className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-sm font-medium outline-none hover:bg-muted/50 focus-visible:ring-2 focus-visible:ring-ring">
        <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-data-[state=open]/disclosure:rotate-90 motion-reduce:transition-none" aria-hidden />
        <span className="min-w-0 break-words">
          <NodeList nodes={node.summary_nodes} />
        </span>
      </CollapsibleTrigger>
      <CollapsibleContent className="flex flex-col gap-3 border-t px-3 py-3">
        <NodeList nodes={node.children} />
      </CollapsibleContent>
    </Collapsible>
  )
}
