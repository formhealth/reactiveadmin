import { JsonNode } from '@/json/JsonNode'
import { Blockquote, Break, Disclosure, Divider, Heading, Paragraph, RichText } from './prose'
import { Empty, NumberNode, BooleanNode, DateNode, DateTimeNode, Ref, LinkNode, Status } from './scalars'
import { Group, Panel, AttributesTable, TableNode } from './containers'
import { Box, List, ListItem, Masked, Toolbar } from './flow'
import { CodeNode, ErrorNode } from './failed'
import { FormNode } from './form'
import { ActionNode } from './interactive'
import { lazyNode } from './lazy'
import { ColumnsNode, Passthrough, TabsNode } from './layout'
import type { NodeRegistry } from './Node'

const Html = lazyNode(() => import('./rich').then((m) => m.Html))
const FrameNode = lazyNode(() => import('./frames').then((m) => m.FrameNode))
const IframeNode = lazyNode(() => import('./frames').then((m) => m.IframeNode))
const ImageNode = lazyNode(() => import('./media').then((m) => m.ImageNode))
const DocumentNode = lazyNode(() => import('./media').then((m) => m.DocumentNode))

export const nodeRegistry: NodeRegistry = {
  empty: Empty,
  text: RichText,
  number: NumberNode,
  boolean: BooleanNode,
  date: DateNode,
  datetime: DateTimeNode,
  ref: Ref,
  link: LinkNode,
  status: Status,
  json: JsonNode,
  html: Html,
  group: Group,
  box: Box,
  panel: Panel,
  attributes_table: AttributesTable,
  table: TableNode,
  action: ActionNode,
  tabs: TabsNode,
  tab: Passthrough,
  columns: ColumnsNode,
  column: Passthrough,
  frame: FrameNode,
  iframe: IframeNode,
  form: FormNode,
  image: ImageNode,
  document: DocumentNode,
  toolbar: Toolbar,
  list: List,
  list_item: ListItem,
  heading: Heading,
  paragraph: Paragraph,
  break: Break,
  divider: Divider,
  disclosure: Disclosure,
  definition_list: AttributesTable,
  blockquote: Blockquote,
  masked: Masked,
  error: ErrorNode,
  code: CodeNode,
}
