import { useSearchParams } from 'react-router'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { uniqueKeys } from '@/lib/keys'
import { NodeList, type NodeProps } from './Node'

const slug = (title?: string | null) => (title ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

// The selected tab lives in `?tab=`, so a view can be shared and survives a reload.
export function TabsNode({ node }: NodeProps) {
  const [params, setParams] = useSearchParams()
  const tabs = node.children ?? []
  const keys = uniqueKeys(tabs.map((tab, i) => slug(tab.title) || `tab-${i + 1}`))
  const selected = keys.find((key) => key === params.get('tab')) ?? keys[0]

  return (
    <Tabs
      value={selected}
      onValueChange={(tab) =>
        setParams(
          (prev) => {
            const next = new URLSearchParams(prev)
            next.set('tab', tab)
            return next
          },
          { replace: true },
        )
      }
    >
      <div className="overflow-x-auto border-b">
        <TabsList variant="line" className="h-10 gap-5 p-0">
          {tabs.map((tab, i) => (
            <TabsTrigger key={keys[i]} value={keys[i]} className="flex-none px-0.5 group-data-horizontal/tabs:after:bottom-0">
              {tab.title}
            </TabsTrigger>
          ))}
        </TabsList>
      </div>
      {tabs.map((tab, i) => (
        <TabsContent key={keys[i]} value={keys[i]} className="mt-2 flex flex-col gap-4">
          <NodeList nodes={tab.children} />
        </TabsContent>
      ))}
    </Tabs>
  )
}

// Only reached when a `tab` or `column` appears outside its parent; the parents render their children themselves.
export const Passthrough = ({ node }: NodeProps) => <NodeList nodes={node.children} />

const GRID = ['md:grid-cols-1', 'md:grid-cols-1', 'md:grid-cols-2', 'md:grid-cols-3', 'md:grid-cols-4']

export function ColumnsNode({ node }: NodeProps) {
  const columns = node.children ?? []
  return (
    <div className={`grid gap-4 ${GRID[Math.min(columns.length, 4)]}`}>
      {columns.map((column, i) => (
        <div key={i} className="flex min-w-0 flex-col gap-4">
          <NodeList nodes={column.children} />
        </div>
      ))}
    </div>
  )
}
