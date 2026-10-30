import { createContext, useContext, type ReactNode } from 'react'
import { useLocation, useNavigate } from 'react-router'

export type NodeContextValue = { resource?: string; id?: string; name?: string | null }

export const NodeContext = createContext<NodeContextValue>({})
export const useNodeContext = () => useContext(NodeContext)

// A template's layout holds the response's own form as a `form` node without a payload; the page that renders the
// layout supplies that form here.
export const OwnFormContext = createContext<ReactNode>(null)

// The query of the view being shown, which a GET form replaces. A page keeps it in the address bar (so back, forward
// and bookmarks work); a view in an overlay has no address and holds it itself.
export type ViewQuery = { search: string; setSearch: (search: string) => void }

export const ViewQueryContext = createContext<ViewQuery | null>(null)

export function useViewQuery(): ViewQuery {
  const provided = useContext(ViewQueryContext)
  const { search } = useLocation()
  const navigate = useNavigate()
  return provided ?? { search, setSearch: (next) => navigate({ search: next }) }
}

// `full` shows complete UUIDs (show-page attribute values); `short` abbreviates them.
export const IdModeContext = createContext<'short' | 'full'>('short')
export const useIdMode = () => useContext(IdModeContext)
