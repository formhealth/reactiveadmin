import type { ComponentType } from 'react'
import type { Node as NodeData, NodeType } from '@/api/generated/model'
import { NodeBoundary } from '@/boundaries/NodeBoundary'
import { isIdentifierName } from '@/lib/ids'
import { Unknown } from './flow'
import { nodeRegistry } from './registry'

export type NodeProps = { node: NodeData }
// `masked` and anything newer than the generated contract are looked up by string.
export type NodeRegistry = Record<NodeType | 'masked' | 'error' | 'code', ComponentType<NodeProps>>

export function Node({ node, registry }: NodeProps & { registry?: Partial<NodeRegistry> }) {
  const lookup = (found?: Partial<Record<string, ComponentType<NodeProps>>>) => found?.[node.type]
  const Component = lookup(registry) ?? lookup(nodeRegistry) ?? Unknown
  return (
    <NodeBoundary type={node.type}>
      {/* Looked up from module-level registries, so the identity is stable across renders. */}
      {/* oxlint-disable-next-line react/static-components */}
      <Component node={node} />
    </NodeBoundary>
  )
}

export function NodeList({ nodes = [] }: { nodes?: NodeData[] }) {
  return nodes.map((node, i) => <Node key={i} node={node} />)
}

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
