import type { AttributeRow, Node as NodeData } from '@/api/generated/model'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { FieldLabelContext } from '@/json/context'
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
  return (
    <Card>
      {node.title && (
        <CardHeader>
          <CardTitle>{node.title}</CardTitle>
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

export const AttributesTable = ({ node }: NodeProps) => (
  <div>
    {node.title && <h2 className="mb-2 text-base font-semibold">{node.title}</h2>}
    <dl className="divide-y">
      {(node.rows ?? []).filter(isAttributeRow).map((row, i) => (
        <div key={i} className="grid gap-0.5 py-2 sm:grid-cols-[12rem_1fr] sm:gap-4">
          <dt className="text-muted-foreground">{row.label}</dt>
          <dd className="flex min-w-0 flex-wrap items-center gap-2 break-words">
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

export const TableNode = ({ node }: NodeProps) => (
  <IdModeContext value="short">
    <Table>
      <TableHeader>
        <TableRow>
          {(node.headers ?? []).map((h, i) => (
            <TableHead key={i}>{h}</TableHead>
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {(node.rows ?? []).map((row, i) => (
          <TableRow key={i}>
            {(isAttributeRow(row) ? row.value : row).map((cell, j) => (
              <TableCell key={j}>
                <NamedNode node={cell} names={[node.headers?.[j]]} />
              </TableCell>
            ))}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  </IdModeContext>
)
