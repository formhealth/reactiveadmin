import { PanelRight } from 'lucide-react'
import type { Sidebar } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet'
import { useIsXl } from '@/hooks/useMediaQuery'
import { NodeContext, type NodeContextValue } from '@/nodes/context'
import { NodeList } from '@/nodes/Node'

// AA sidebar sections (info panels, extra filters) as cards.
export function SidebarSections({ sidebars, ctx = {} }: { sidebars: Sidebar[]; ctx?: NodeContextValue }) {
  return (
    <NodeContext value={ctx}>
      {sidebars.map((sidebar, i) => (
        <Card key={i} size="sm">
          <CardHeader>
            <CardTitle>{sidebar.title}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            <NodeList nodes={sidebar.layout} />
          </CardContent>
        </Card>
      ))}
    </NodeContext>
  )
}

type IndexFrameProps = { sidebars?: Sidebar[]; ctx?: NodeContextValue; header: (trigger: React.ReactNode) => React.ReactNode; children: React.ReactNode }

// From xl up the sections sit in a right rail; below it they open from a button in the page header.
export function WithSidebars({ sidebars = [], ctx, header, children }: IndexFrameProps) {
  const rail = useIsXl()
  if (sidebars.length === 0) return <>{header(null)}{children}</>

  const label = sidebars.length === 1 ? sidebars[0].title : 'Details'
  const trigger = rail ? null : (
    <Sheet>
      <SheetTrigger asChild>
        <Button variant="outline">
          <PanelRight />
          {label}
        </Button>
      </SheetTrigger>
      <SheetContent side="right" className="gap-0 overflow-y-auto p-0">
        <SheetHeader>
          <SheetTitle>{label}</SheetTitle>
          <SheetDescription className="sr-only">Information about this list</SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-3 p-4">
          <SidebarSections sidebars={sidebars} ctx={ctx} />
        </div>
      </SheetContent>
    </Sheet>
  )

  return (
    <>
      {header(trigger)}
      {rail ? (
        <div className="grid grid-cols-[minmax(0,1fr)_18rem] items-start gap-6">
          <div className="flex min-w-0 flex-col gap-4">{children}</div>
          <aside aria-label="Sidebar" className="sticky top-4 flex flex-col gap-3">
            <SidebarSections sidebars={sidebars} ctx={ctx} />
          </aside>
        </div>
      ) : (
        children
      )}
    </>
  )
}
