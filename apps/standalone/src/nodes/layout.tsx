import { useContext, type CSSProperties } from 'react'
import { useSearchParams } from 'react-router'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { uniqueKeys } from '@/lib/keys'
import { cn } from '@/lib/utils'
import { columnLimits, columnsLayout } from './columns'
import { NodeList, type NodeProps } from './Node'
import { TabParamsContext } from './tabParams'

const slug = (title?: string | null) => (title ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')

// The selected tab lives in the query (`?tab=`, `?tab2=`, ... per group), so a view can be shared and survives a reload.
export function TabsNode({ node }: NodeProps) {
  const [params, setParams] = useSearchParams()
  const param = useContext(TabParamsContext)?.get(node) ?? 'tab'
  const tabs = node.children ?? []
  const keys = uniqueKeys(tabs.map((tab, i) => slug(tab.title) || `tab-${i + 1}`))
  const selected = keys.find((key) => key === params.get(param)) ?? keys[0]

  return (
    <Tabs
      value={selected}
      onValueChange={(tab) =>
        setParams(
          (prev) => {
            const next = new URLSearchParams(prev)
            next.set(param, tab)
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

export function ColumnsNode({ node }: NodeProps) {
  const columns = node.children ?? []
  const { tracks, className } = columnsLayout(columns)
  return (
    // A query container has no width of its own content, so it takes all it's given.
    <div className="@container w-full min-w-0">
      <div style={{ '--tracks': tracks } as CSSProperties} className={cn('grid gap-4', className)}>
        {columns.map((column, i) => {
          const limits = columnLimits(column)
          return (
            <div key={i} style={limits.style} className={cn('flex min-w-0 flex-col gap-4', limits.className)}>
              <NodeList nodes={column.children} />
            </div>
          )
        })}
      </div>
    </div>
  )
}
