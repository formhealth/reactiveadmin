import { LayoutGrid, Newspaper, Rows3, Table2, type LucideIcon } from 'lucide-react'
import type { ResourceMetaIndexViewsItem } from '@/api/generated/model'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { humanize } from '@/lib/humanize'

const ICONS: Record<string, LucideIcon> = { table: Table2, grid: LayoutGrid, blog: Newspaper, block: Rows3 }

type ViewSwitcherProps = { views: ResourceMetaIndexViewsItem[]; current?: string; onChange: (view: string) => void }

// Resources that declare several `index as:` presenters.
export function ViewSwitcher({ views, current, onChange }: ViewSwitcherProps) {
  const value = views.some((view) => view.as === current) ? current : views.find((view) => view.default)?.as
  return (
    <Tabs value={value} onValueChange={onChange}>
      <TabsList aria-label="View">
        {views.map((view) => {
          const Icon = ICONS[view.as]
          return (
            <TabsTrigger key={view.as} value={view.as} aria-controls={undefined} className="flex-none px-2.5">
              {Icon && <Icon aria-hidden />}
              {view.label ?? humanize(view.as)}
            </TabsTrigger>
          )
        })}
      </TabsList>
    </Tabs>
  )
}
