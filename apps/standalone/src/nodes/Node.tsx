import { useContext, useMemo, type ComponentType, type ReactNode } from 'react'
import type { Node as NodeData, NodeType } from '@/api/generated/model'
import { NodeBoundary } from '@/boundaries/NodeBoundary'
import { isIdentifierName } from '@/lib/ids'
import { Unknown } from './flow'
import { nodeRegistry } from './registry'
import { TabParamsContext, tabParams } from './tabParams'

export type NodeProps = { node: NodeData }
// `masked` and anything newer than the generated contract are looked up by string.
export type NodeRegistry = Record<NodeType | 'masked' | 'error' | 'code', ComponentType<NodeProps>>

// Names the tab groups' query params for everything inside it: the outermost list or node of a tree does, unless a
// page has already named them for all its trees (layout and sidebars). A `prefix` starts a scope of its own, for
// layouts the page's walk can't see (a form's content).
export function TabScope({ nodes, prefix, children }: { nodes: NodeData[]; prefix?: string; children: ReactNode }) {
  const scope = useContext(TabParamsContext)
  const own = useMemo(() => (scope && !prefix ? undefined : tabParams(nodes, prefix)), [scope, nodes, prefix])
  return own ? <TabParamsContext value={own}>{children}</TabParamsContext> : children
}

export function Node({ node, registry }: NodeProps & { registry?: Partial<NodeRegistry> }) {
  const lookup = (found?: Partial<Record<string, ComponentType<NodeProps>>>) => found?.[node.type]
  const Component = lookup(registry) ?? lookup(nodeRegistry) ?? Unknown
  const nodes = useMemo(() => [node], [node])
  return (
    <TabScope nodes={nodes}>
      <NodeBoundary type={node.type}>
        {/* Looked up from module-level registries, so the identity is stable across renders. */}
        {/* oxlint-disable-next-line react/static-components */}
        <Component node={node} />
      </NodeBoundary>
    </TabScope>
  )
}

export function NodeList({ nodes = EMPTY }: { nodes?: NodeData[] }) {
  return (
    <TabScope nodes={nodes}>
      {nodes.map((node, i) => (
        <Node key={i} node={node} />
      ))}
    </TabScope>
  )
}

const EMPTY: NodeData[] = []

// Identifier columns and rows (`id`, `ref_id`, ...) read as code, so text and numbers render mono.
export function NamedNode({ node, names }: { node: NodeData; names: (string | undefined)[] }) {
  const mono = (node.type === 'text' || node.type === 'number') && names.some(isIdentifierName)
  return mono ? (
    <span className="font-mono font-normal">
      <Node node={node} />
    </span>
  ) : (
    <Node node={node} />
  )
}
