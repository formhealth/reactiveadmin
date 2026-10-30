import type { Scope } from '@/api/generated/model'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { humanize } from '@/lib/humanize'

type ScopeTabsProps = { scopes: Scope[]; current?: string; onChange: (scope: string) => void }

const Count = ({ count }: { count?: number | null }) =>
  count != null && (
    <Badge variant="secondary" className="tabular-nums">
      {count.toLocaleString()}
    </Badge>
  )

// Scopes filter one list, so there are no tab panels for `aria-controls` to point at.
// Consecutive scopes with the same AA `group:` form one run; each run is its own segmented control.
const runsOf = (scopes: Scope[]) =>
  scopes.reduce<{ group: string | null; scopes: Scope[] }[]>((runs, scope) => {
    const group = scope.group ?? null
    if (runs.at(-1)?.group === group) runs.at(-1)!.scopes.push(scope)
    else runs.push({ group, scopes: [scope] })
    return runs
  }, [])

export function ScopeTabs({ scopes, current, onChange }: ScopeTabsProps) {
  if (!scopes.some((scope) => scope.group))
    return (
      <Tabs value={current} onValueChange={onChange}>
        <div className="overflow-x-auto border-b">
          <TabsList variant="line" aria-label="Scopes" className="h-10 gap-5 p-0">
            {scopes.map((scope) => (
              <TabsTrigger key={scope.id} value={scope.id} aria-controls={undefined} className="flex-none px-0.5 group-data-horizontal/tabs:after:bottom-0">
                {scope.name}
                <Count count={scope.count} />
              </TabsTrigger>
            ))}
          </TabsList>
        </div>
      </Tabs>
    )

  return (
    <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
      {runsOf(scopes).map(({ group, scopes: run }, i) => (
        <div key={`${group}-${i}`} className="flex items-center gap-2">
          {group && <span className="text-sm text-muted-foreground">{humanize(group)}</span>}
          <Tabs value={run.some((scope) => scope.id === current) ? current : ''} onValueChange={onChange}>
            <TabsList aria-label={group ? humanize(group) : 'Scopes'} className="h-auto flex-wrap">
              {run.map((scope) => (
                <TabsTrigger key={scope.id} value={scope.id} aria-controls={undefined} className="flex-none px-2.5">
                  {scope.name}
                  <Count count={scope.count} />
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        </div>
      ))}
    </div>
  )
}
