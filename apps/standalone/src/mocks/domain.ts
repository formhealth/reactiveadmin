import type { Action, Column, FormResponse, Node, PageResponse, Row, ShowResponse } from '@/api/generated/model'
import { batchForm, teamHistory } from './classic'
import { day, uuid } from './fixtures'
import { authorActions } from './authors'

const text = (value: string): Node => ({ type: 'text', text: value })
const table = (headers: string[], rows: Node[][]): Node => ({ type: 'table', headers, rows })
const attributes = (rows: [string, Node][]): Node => ({ type: 'attributes_table', rows: rows.map(([label, value]) => ({ label, value: [value] })) })

// Author show page: tabs, responsive columns, an inline (non-GET) action node, and a frame node.
export const authorShowLayout = (row: Row): Node[] => {
  const { id } = row
  const name = row.display_name ?? ''
  const welcome: Action = {
    key: 'resend_welcome',
    label: 'Resend welcome email',
    kind: 'member',
    placement: 'inline',
    method: 'post',
    href: `/admin/authors/${id}/resend_welcome`,
    api_path: `/api/admin/authors/${id}/resend_welcome`,
    confirm: `Send the welcome email to ${name} again?`,
    enabled: true,
  }
  return [
    {
      type: 'tabs',
      children: [
        {
          type: 'tab',
          title: 'Overview',
          children: [
            {
              type: 'columns',
              children: [
                {
                  type: 'column',
                  children: [
                    attributes([
                      ['ID', row.cells.id],
                      ['Name', row.cells.name],
                      ['External ID', row.cells.external_id],
                      ['State', row.cells.state],
                      ['Status', row.cells.status],
                      ['Created At', row.cells.created_at],
                    ]),
                    { type: 'action', action: welcome },
                  ],
                },
                {
                  type: 'column',
                  children: [
                    {
                      type: 'panel',
                      title: 'Program',
                      children: [
                        attributes([
                          ['Primary editor', { type: 'ref', label: uuid(90), ref: { resource: 'editors', id: uuid(90) } }],
                          ['Joined', { type: 'date', value: day(-120).slice(0, 10) }],
                          ['Next deadline', { type: 'datetime', value: day(6).replace(/T.*/, 'T15:30:00.000Z') }],
                        ]),
                      ],
                    },
                    { type: 'panel', title: 'Notes', children: [{ type: 'html', html: '<p>Prefers morning check-ins. Files copy from a <strong>laptop</strong> and a tablet.</p>' }] },
                  ],
                },
              ],
            },
            {
              type: 'box',
              tag: 'div',
              layout: { display: 'flex', direction: 'row', breakpoint: 'lg', gap: 4 },
              children: [
                {
                  type: 'box',
                  width: '1/2',
                  children: [
                    {
                      type: 'panel',
                      title: 'Contact',
                      children: [
                        attributes([
                          ['Email', { type: 'text', text: `${name.toLowerCase().replace(/\W+/g, '.')}@example.com` }],
                          ['Phone', { type: 'text', text: '(617) 555-0142' }],
                          ['Portal token', { type: 'masked' }],
                        ]),
                        {
                          type: 'toolbar',
                          align: 'end',
                          children: [
                            { type: 'link', label: 'Edit contact', href: `/admin/authors/${id}/edit` },
                            { type: 'action', action: { ...welcome, key: 'resend_welcome_toolbar' } },
                          ],
                        },
                      ],
                    },
                  ],
                },
                {
                  type: 'box',
                  width: '1/2',
                  children: [
                    {
                      type: 'panel',
                      title: 'Team',
                      children: [
                        {
                          type: 'list',
                          ordered: false,
                          children: [
                            { type: 'list_item', children: [{ type: 'text', text: 'Amelia Chen, lead editor' }] },
                            { type: 'list_item', children: [{ type: 'text', text: 'Marcus Johnson' }] },
                            { type: 'list_item', children: [{ type: 'text', text: 'Priya Raman, copy editor' }] },
                          ],
                        },
                        {
                          type: 'toolbar',
                          children: [
                            { type: 'link', label: 'Team history', href: `/admin/authors/${id}/team_history` },
                            { type: 'link', label: 'New member', href: `/admin/authors/${id}/team_members/new` },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
        { type: 'tab', title: 'Team', children: [{ type: 'frame', src: `/admin/authors/${id}/team_history`, html: teamHistory(id), title: 'Team history' }] },
        {
          type: 'tab',
          title: 'Activity',
          children: [
            table(
              ['When', 'Event', 'By'],
              [
                [{ type: 'datetime', value: day(-2).replace(/T.*/, 'T13:05:00.000Z') }, text('Draft saved: 1,240 words'), text('Author')],
                [{ type: 'datetime', value: day(-5).replace(/T.*/, 'T16:40:00.000Z') }, text('Post published'), text('Sarah Chen')],
                [{ type: 'datetime', value: day(-9).replace(/T.*/, 'T11:15:00.000Z') }, text('Message sent'), text('Lauren Thompson')],
              ],
            ),
          ],
        },
      ],
    },
  ]
}

export const authorShow = (row: Row): ShowResponse => ({
  resource: 'authors',
  id: row.id,
  title: `Author ${row.display_name}`,
  display_name: row.display_name,
  permissions: { show: true },
  actions: authorActions(row.id, 'header'),
  layout: authorShowLayout(row),
})

type Approval = { id: string; headline: string; author: string; status: 'pending' | 'approved' | 'denied'; requested: string }

export const approvals: Approval[] = [
  { id: '1042', headline: 'Spring issue cover story', author: 'Alex Nguyen', status: 'pending', requested: day(-6) },
  { id: '1043', headline: 'Interview with the new editor', author: 'Jordan Patel', status: 'approved', requested: day(-12) },
  { id: '1044', headline: 'Opinion: on deadlines', author: 'Sam Garcia', status: 'denied', requested: day(-20) },
  { id: '1045', headline: 'Weekly digest, issue 12', author: 'Taylor Johnson', status: 'pending', requested: day(-2) },
]

const paName = (pa: Approval) => `AP-${pa.id} · ${pa.headline}`

const statusNode = (pa: Approval): Node => ({ type: 'status', label: pa.status[0].toUpperCase() + pa.status.slice(1), variant: { pending: 'warning', approved: 'success', denied: 'danger' }[pa.status] as 'warning' })

// Native rung: the action's template was Formtastic-only, so its path answers with a FormResponse.
const approve = (pa: Approval, placement: Action['placement']): Action => ({
  key: 'approve',
  label: 'Approve',
  kind: 'member',
  placement,
  method: 'get',
  href: `/admin/content_approvals/${pa.id}/approve`,
  view: { mode: 'native', path: `/api/admin/content_approvals/${pa.id}/approve`, presentation: 'dialog' },
  enabled: pa.status === 'pending',
  disabled_reason: pa.status === 'pending' ? null : `Already ${pa.status}`,
})

const printLetter = (pa: Approval): Action => ({
  key: 'print_proof',
  label: 'Print proof',
  kind: 'custom',
  placement: 'header',
  method: 'get',
  href: `/admin/content_approvals/${pa.id}/print_proof`,
  supported: false,
  disabled_reason: 'Opens a print dialog from custom JavaScript',
  enabled: true,
})

export const approvalColumns: Column[] = [
  ['id', 'ID'],
  ['author', 'Author'],
  ['headline', 'Headline'],
  ['status', 'Status'],
  ['requested_at', 'Requested'],
].map(([key, label]) => ({ key, label, sortable: key !== 'status' }))

export const approvalRows: Row[] = approvals.map((pa) => ({
  id: pa.id,
  display_name: paName(pa),
  permissions: { show: true, update: false, destroy: false },
  actions: [approve(pa, 'row')],
  cells: {
    id: text(pa.id),
    author: text(pa.author),
    headline: text(pa.headline),
    status: statusNode(pa),
    requested_at: { type: 'date', value: pa.requested.slice(0, 10) },
  },
}))

export const approvalShow = (pa: Approval): ShowResponse => ({
  resource: 'content_approvals',
  id: pa.id,
  title: `Content Approval #${pa.id}`,
  display_name: paName(pa),
  permissions: { show: true },
  actions: [approve(pa, 'header'), printLetter(pa)],
  layout: [
    attributes([
      ['ID', text(pa.id)],
      ['Author', text(pa.author)],
      ['Headline', text(pa.headline)],
      ['Status', statusNode(pa)],
      ['Requested', { type: 'date', value: pa.requested.slice(0, 10) }],
    ]),
  ],
})

export const approveForm = (pa: Approval): FormResponse => ({
  resource: 'content_approvals',
  id: pa.id,
  title: `Approve ${paName(pa)}`,
  action: { method: 'post', path: `/api/admin/content_approvals/${pa.id}/approve` },
  permissions: { update: true },
  form: {
    sections: [
      {
        kind: 'inputs',
        fields: [
          { name: 'reference_number', param: 'approval[reference_number]', label: 'Reference number', control: 'text', required: true, value: null, hint: 'From the approval letter.' },
          { name: 'valid_through', param: 'approval[valid_through]', label: 'Valid through', control: 'date', required: false, value: day(180).slice(0, 10) },
          { name: 'notes', param: 'approval[notes]', label: 'Notes', control: 'textarea', required: false, value: null, input_html: { rows: 3 } },
        ],
      },
    ],
  },
})

export const attachmentRows = (page: number, perPage: number): Row[] =>
  Array.from({ length: perPage }, (_, i) => {
    const n = (page - 1) * perPage + i
    const oversized = n % 4 === 0
    return {
      id: String(9000 + n),
      permissions: { show: true },
      cells: {
        id: text(String(9000 + n)),
        author: text(['Alex Nguyen', 'Jordan Patel', 'Sam Garcia', 'Taylor Johnson'][n % 4]),
        file: text(['cover.png', 'annual-report.pdf', 'headshot.jpg', 'notes.docx'][n % 4]),
        size: text(['1.2 MB', '340 KB', '2.8 MB', '84 KB'][n % 4]),
        flag: oversized ? { type: 'status', label: 'Oversized', variant: 'warning' } : { type: 'empty' },
        uploaded_at: { type: 'datetime', value: day(-n).replace(/T.*/, 'T12:30:00.000Z') },
      },
    }
  })

export const attachmentColumns: Column[] = [
  ['id', 'ID'],
  ['author', 'Author'],
  ['file', 'File'],
  ['size', 'Size'],
  ['flag', 'Flag'],
  ['uploaded_at', 'Uploaded'],
].map(([key, label]) => ({ key, label, sortable: key === 'uploaded_at' || key === 'author' }))

export const pages: Record<string, PageResponse> = {
  batch_operations: {
    key: 'batch_operations',
    title: 'Batch Operations',
    actions: [{ key: 'refresh', label: 'Refresh history', kind: 'custom', placement: 'header', method: 'post', api_path: '/api/admin/_pages/batch_operations/refresh', enabled: true }],
    layout: [
      {
        type: 'panel',
        title: 'Recent batches',
        children: [
          table(
            ['Operation', 'Started', 'Status', 'Records'],
            [
              [text('Lift expired embargoes'), { type: 'datetime', value: day(0).replace(/T.*/, 'T09:00:00.000Z') }, { type: 'status', label: 'Complete', variant: 'success' }, { type: 'number', value: 18 }],
              [text('Republish failed posts'), { type: 'datetime', value: day(-1).replace(/T.*/, 'T17:45:00.000Z') }, { type: 'status', label: 'Running', variant: 'info' }, { type: 'number', value: 34 }],
              [text('Backfill publisher ids'), { type: 'datetime', value: day(-4).replace(/T.*/, 'T14:10:00.000Z') }, { type: 'status', label: 'Failed', variant: 'danger' }, { type: 'number', value: 1240 }],
            ],
          ),
        ],
      },
      { type: 'panel', title: 'Start a batch', children: [{ type: 'frame', src: '/admin/batch_operations', html: batchForm(), title: 'Start a batch' }] },
    ],
  },
}
