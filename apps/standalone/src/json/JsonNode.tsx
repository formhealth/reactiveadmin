import { Empty } from '@/nodes/scalars'
import { useIdMode, useNodeContext } from '@/nodes/context'
import type { NodeProps } from '@/nodes/Node'
import { useFieldLabel } from './context'
import { auditedChanges } from './audit'
import { LazyJsonDiff as JsonDiff, LazyJsonView as JsonView } from './lazy'
import { JsonSummary } from './JsonSummary'
import { kindOf, sizeLabel, sizeOf } from './tree'

const PREVIEW = 60

const preview = (value: unknown) => {
  const text = JSON.stringify(value) ?? ''
  return text.length > PREVIEW ? `${text.slice(0, PREVIEW)}…` : text
}

function Collapsible({ summary, children }: { summary: string; children: React.ReactNode }) {
  return (
    <details className="group max-w-full text-xs">
      <summary className="cursor-pointer truncate rounded-sm font-mono text-muted-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring">{summary}</summary>
      <div className="mt-1">{children}</div>
    </details>
  )
}

export function JsonNode({ node }: NodeProps) {
  const ctx = useNodeContext()
  // Table cells stay one line; a record's own attributes show the tree outright.
  const compact = useIdMode() === 'short'
  const fieldLabel = useFieldLabel()
  const label = fieldLabel || 'JSON'

  if (node.summary) return <JsonSummary summary={node.summary} expandPath={node.expand_path} label={label} compact={compact} />
  if (node.value == null) return <Empty />

  const { value } = node
  if (kindOf(value) === 'scalar') return <code className="font-mono text-xs break-words">{typeof value === 'string' ? value : JSON.stringify(value)}</code>

  const changes = auditedChanges(node, { resource: ctx.resource, label: fieldLabel })
  if (changes) {
    const diff = <JsonDiff changes={changes} raw={value} />
    return compact ? <Collapsible summary={`${sizeOf(changes)} changes`}>{diff}</Collapsible> : diff
  }

  const view = <JsonView value={value} label={label} maxHeight={compact ? '20rem' : '40rem'} />
  return compact ? <Collapsible summary={`${sizeLabel(kindOf(value), sizeOf(value))} · ${preview(value)}`}>{view}</Collapsible> : view
}
