import type { AttributeRow, Node as NodeData } from '@/api/generated/model'
import { Card, CardAction, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { FieldLabelContext } from '@/json/context'
import { cn } from '@/lib/utils'
import { IdModeContext } from './context'
import { NamedNode, NodeList, type NodeProps } from './Node'

const isAttributeRow = (row: AttributeRow | NodeData[]): row is AttributeRow => !Array.isArray(row)

export const Group = ({ node }: NodeProps) => (
  <span className="inline-flex flex-wrap items-center gap-2">
    <NodeList nodes={node.children} />
  </span>
)

// Toolbars directly inside a panel are its footer actions.
export function Panel({ node }: NodeProps) {
  const children = node.children ?? []
  const footer = children.filter((child) => child.type === 'toolbar')
  const body = children.filter((child) => child.type !== 'toolbar')
  const headerActions = node.header_actions ?? []
  return (
    <Card>
      {(node.title || headerActions.length > 0) && (
        <CardHeader>
          <CardTitle>{node.title}</CardTitle>
          {headerActions.length > 0 && (
            <CardAction className="flex items-center gap-2">
              <NodeList nodes={headerActions} />
            </CardAction>
          )}
        </CardHeader>
      )}
      <CardContent className="flex flex-col gap-4">
        <NodeList nodes={body} />
      </CardContent>
      {footer.length > 0 && (
        <CardFooter className="flex-col items-stretch gap-2">
          <NodeList nodes={footer} />
        </CardFooter>
      )}
    </Card>
  )
}

// Labels share one column, as wide as the longest (up to 12rem), and stack over their values when the panel is narrow.
export const AttributesTable = ({ node }: NodeProps) => (
  // A query container has no width of its own content, so it takes all it's given (also inside a flex value).
  <div className="@container w-full min-w-0">
    {node.title && <h2 className="mb-2 text-base font-semibold">{node.title}</h2>}
    <dl className="grid divide-y @md:grid-cols-[fit-content(12rem)_minmax(0,1fr)] @md:gap-x-4">
      {(node.rows ?? []).filter(isAttributeRow).map((row, i) => (
        <div key={i} className="grid gap-y-0.5 py-2 @md:col-span-2 @md:grid-cols-subgrid">
          <dt className="text-muted-foreground wrap-anywhere">{row.label}</dt>
          <dd className="flex min-w-0 flex-wrap items-center gap-2 wrap-anywhere">
            <IdModeContext value="full">
              <FieldLabelContext value={row.label}>
                {row.value.map((value, j) => (
                  <NamedNode key={j} node={value} names={[row.label]} />
                ))}
              </FieldLabelContext>
            </IdModeContext>
          </dd>
        </div>
      ))}
    </dl>
  </div>
)

// Unlike index tables, long cells wrap, past 15rem: a panel's table shares the page, so a sentence shouldn't make it
// scroll sideways. The cap, rather than plain wrapping, keeps a narrow panel from crushing cells to a word per line;
// `fit-content` lets what can't wrap (a datetime, an external link) widen the column rather than overflow it. A query
// container has no content width to fit, so a cell holding one is at least the cap, and wider for what beside it can't
// wrap.
const holdsContainer = (node: NodeData): boolean =>
  node.type === 'attributes_table' ||
  node.type === 'definition_list' ||
  node.type === 'columns' ||
  ((node.type === 'box' || node.type === 'group') && (node.children ?? []).some(holdsContainer))

export const TableNode = ({ node }: NodeProps) => (
  <IdModeContext value="short">
    <Table>
      <TableHeader>
        <TableRow>
          {(node.headers ?? []).map((h, i) => (
            <TableHead key={i} className="whitespace-normal">
              {h}
            </TableHead>
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {(node.rows ?? []).map((row, i) => (
          <TableRow key={i}>
            {(isAttributeRow(row) ? row.value : row).map((cell, j) => (
              <TableCell key={j} className="whitespace-normal">
                <div className={cn('grid w-max wrap-anywhere', holdsContainer(cell) ? 'grid-cols-[minmax(15rem,max-content)]' : 'grid-cols-[fit-content(15rem)]')}>
                  <NamedNode node={cell} names={[node.headers?.[j]]} />
                </div>
              </TableCell>
            ))}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </IdModeContext>
)
