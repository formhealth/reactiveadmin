import { createContext } from 'react'
import type { Node as NodeData } from '@/api/generated/model'

export const TabParamsContext = createContext<Map<NodeData, string> | undefined>(undefined)

const nested = (node: NodeData): NodeData[] => [
  ...(node.header_actions ?? []),
  ...(node.summary_nodes ?? []),
  ...(node.children ?? []),
  ...(node.rows ?? []).flatMap((row) => (Array.isArray(row) ? row : row.value)),
]

// Each tab group on a page keeps its own query param, so picking a tab in one leaves the others alone. The first keeps
// the plain `?tab=` that single-group links already use; the rest are numbered in page order.
export function tabParams(nodes: NodeData[], prefix = 'tab'): Map<NodeData, string> {
  const params = new Map<NodeData, string>()
  const walk = (node: NodeData) => {
    if (node.type === 'tabs') params.set(node, params.size ? `${prefix}${params.size + 1}` : prefix)
    nested(node).forEach(walk)
  }
  nodes.forEach(walk)
  return params
}
