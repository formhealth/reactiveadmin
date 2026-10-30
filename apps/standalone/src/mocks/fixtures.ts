import type { Action, BatchAction, Column, Filter, MenuItem, Node, Permissions, ResourceMeta, ResourceSummary, Scope, Site } from '@/api/generated/model'
import { formatDay, parseDay } from '@/lib/datetime'

const ref = (resource: string, id: string | number, label: string): Node => ({
  type: 'ref',
  label,
  ref: { resource, id: String(id) },
})

export const editors = ['Amelia Chen', 'Marcus Webb', 'Priya Raman', 'Tomas Alvarez', 'Grace Okafor']
const firstNames = ['Alex', 'Jordan', 'Sam', 'Taylor', 'Morgan', 'Casey', 'Riley', 'Jamie', 'Avery', 'Quinn', 'Drew', 'Cameron']
const lastNames = ['Nguyen', 'Patel', 'Garcia', 'Johnson', 'Kim', 'Rossi', 'Haddad', 'Murphy', 'Silva', 'Novak']
const publicationStatuses = [
  { value: 'pending', label: 'Pending', variant: 'neutral' },
  { value: 'published', label: 'Published', variant: 'success' },
  { value: 'review_failed', label: 'Review failed', variant: 'danger' },
  { value: 'rejected', label: 'Rejected', variant: 'warning' },
] as const

export type Post = {
  id: number
  author_id: number
  author: string
  editor_id: number
  published_on: string
  embargo_until: string | null
  publication_status: (typeof publicationStatuses)[number]['value']
  seo_checked: boolean
  created_at: string
}

export const day = (offset: number) => new Date(Date.UTC(2026, 9, 16) + offset * 864e5).toISOString()

export const posts: Post[] = Array.from({ length: 120 }, (_, i) => ({
  id: 5000 + i,
  author_id: 100 + ((i * 7) % 45),
  author: `${firstNames[i % firstNames.length]} ${lastNames[(i * 3) % lastNames.length]}`,
  editor_id: (i % editors.length) + 1,
  published_on: day(-(i * 2) - 1).slice(0, 10),
  embargo_until: i % 5 === 0 ? day(((i * 3) % 40) - 10).slice(0, 10) : null,
  publication_status: publicationStatuses[(i * 5) % 7 % 4].value,
  seo_checked: i % 4 !== 0,
  created_at: day(-(i * 2) - 1).replace(/T.*/, `T${String(8 + (i % 10)).padStart(2, '0')}:${String((i * 13) % 60).padStart(2, '0')}:00.000Z`),
}))

export const postName = (e: Post) => `${e.author} (${formatDay(parseDay(e.published_on)!)})`

export const isEmbargoed = (e: Post) => !!e.embargo_until && e.embargo_until >= day(0).slice(0, 10)

export const scopeDefs = [
  { id: 'all', name: 'All', match: () => true },
  { id: 'embargoed', name: 'Embargoed', match: isEmbargoed },
  { id: 'not_embargoed', name: 'Not Embargoed', match: (e: Post) => !isEmbargoed(e) },
  { id: 'review_failed', name: 'Review Failed', match: (e: Post) => e.publication_status === 'review_failed' },
]

export const columns: Column[] = [
  ['id', 'ID'],
  ['author', 'Author', 'author_id'],
  ['editor', 'Editor', 'editor_id'],
  ['published_on', 'Published On'],
  ['embargo_until', 'Embargo Until'],
  ['publication_status', 'Publication Status'],
  ['seo_data', 'SEO Data'],
  ['publisher_url', 'Publisher URL'],
  ['created_at', 'Created At'],
].map(([key, label, sort_key]) => ({
  key,
  label,
  sortable: key !== 'seo_data' && key !== 'publisher_url',
  sort_key: sort_key ?? key,
}))

const embargoNode = (e: Post): Node =>
  e.embargo_until
    ? { type: 'status', label: isEmbargoed(e) ? `Embargoed until ${e.embargo_until}` : 'Embargo expired', variant: isEmbargoed(e) ? 'warning' : 'neutral' }
    : { type: 'empty' }

const statusNode = (e: Post): Node => {
  const { label, variant } = publicationStatuses.find((s) => s.value === e.publication_status)!
  return { type: 'status', label, variant }
}

const seoNode = (e: Post): Node => ({
  type: 'status',
  label: e.seo_checked ? 'Checked' : 'Missing',
  variant: e.seo_checked ? 'info' : 'danger',
})

const publisherLink = (e: Post): Node =>
  e.publication_status === 'published'
    ? { type: 'link', label: `ref-${e.id}`, href: `https://publisher.example.com/posts/${e.id}`, external: true }
    : { type: 'empty' }

export const cellsFor = (e: Post): Record<string, Node> => ({
  id: { type: 'text', text: String(e.id) },
  author: ref('authors', e.author_id, e.author),
  editor: ref('editors', e.editor_id, editors[e.editor_id - 1]),
  published_on: { type: 'date', value: e.published_on },
  embargo_until: embargoNode(e),
  publication_status: statusNode(e),
  seo_data: seoNode(e),
  publisher_url: publisherLink(e),
  created_at: { type: 'datetime', value: e.created_at },
})

export const showLayout = (e: Post): Node[] => [
  {
    type: 'attributes_table',
    rows: [
      ['ID', { type: 'text', text: String(e.id) }],
      ['Author', ref('authors', e.author_id, e.author)],
      ['Editor', ref('editors', e.editor_id, editors[e.editor_id - 1])],
      ['Published On', { type: 'date', value: e.published_on }],
      ['Embargo Until', embargoNode(e)],
      ['Publication Status', statusNode(e)],
      ['Needs Review', { type: 'boolean', value: e.publication_status === 'review_failed' }],
      ['Publisher URL', publisherLink(e)],
      ['Created At', { type: 'datetime', value: e.created_at }],
    ].map(([label, value]) => ({ label: label as string, value: [value as Node] })),
  },
  {
    type: 'panel',
    title: 'SEO Data',
    children: [
      seoNode(e),
      {
        type: 'json',
        value: {
          publisher: 'Acme Media',
          reader_id: `XYZ${e.author_id}00${e.id}`,
          indexing: { active: e.seo_checked, price_cents: 3500, checked_at: e.created_at },
          plans: [{ code: 'WEB-1', primary: true }],
        },
      },
      { type: 'html', html: `<p><strong>Notes:</strong> SEO check <em>cached</em> for 24h.</p><ul><li>Indexing: allowed</li><li>Sitemap: included</li></ul>` },
    ],
  },
]

const scopes = scopeDefs.map(({ id, name }): Scope => ({ id, name }))

const ranged = (name: string, label: string): Filter => ({
  name,
  label,
  control: 'date_range',
  range: { from: `${name}_gteq`, to: `${name}_lteq` },
})

export const filters: Filter[] = [
  {
    name: 'author_id',
    label: 'Author ID',
    control: 'text',
    predicates: [
      { param: 'author_id_eq', label: 'Equals' },
      { param: 'author_id_gteq', label: 'Greater or equal' },
    ],
  },
  {
    name: 'editor',
    label: 'Editor',
    control: 'typeahead',
    param: 'editor_id_eq',
    options: editors.map((label, i) => ({ label, value: String(i + 1) })),
  },
  ranged('published_on', 'Published On'),
  ranged('embargo_until', 'Embargo Until'),
  {
    name: 'publication_status',
    label: 'Publication Status',
    control: 'select',
    param: 'publication_status_eq',
    options: publicationStatuses.map(({ value, label }) => ({ value, label })),
  },
  ranged('created_at', 'Created At'),
]

const batchActions: BatchAction[] = [
  { key: 'lift_embargo', label: 'Lift embargo', inputs: [] },
  {
    key: 'set_embargo',
    label: 'Set embargo date',
    confirm: 'Embargoed posts are not published until the date you choose.',
    inputs: [
      {
        name: 'embargo_until',
        param: 'batch_action_inputs[embargo_until]',
        label: 'Embargo until',
        control: 'date',
        required: true,
        hint: 'Posts are published on this date.',
      },
    ],
  },
  { key: 'destroy', label: 'Delete', confirm: "Delete the selected posts? This can't be undone.", inputs: [] },
]

const postActionItems: Action[] = [
  {
    key: 'publish_pending',
    label: 'Publish pending',
    kind: 'collection',
    placement: 'header',
    method: 'post',
    href: '/admin/posts/publish_pending',
    api_path: '/api/admin/posts/publish_pending',
    confirm: 'Publish every pending post to the publisher now?',
    enabled: true,
  },
  { key: 'sync_publisher', label: 'Sync from publisher', kind: 'collection', placement: 'header', method: 'post', href: '/admin/posts/sync_publisher', api_path: '/api/admin/posts/sync_publisher', enabled: true },
  {
    key: 'legacy_import',
    label: 'Legacy import',
    kind: 'custom',
    placement: 'header',
    method: 'get',
    href: '/admin/posts/legacy_import',
    supported: false,
    disabled_reason: "Uses a custom upload widget that isn't supported here yet",
    enabled: true,
  },
]

const FULL: Permissions = { index: true, show: true, create: true, update: true, destroy: true }
const READ_ONLY: Permissions = { index: true, show: true, create: false, update: false, destroy: false }

const resource = (key: string, label: string, plural_label: string, extra: Partial<ResourceMeta> = {}): ResourceMeta => ({
  key,
  label,
  plural_label,
  actions: ['index', 'show'],
  permissions: { index: true, show: true },
  filters: [],
  scopes: [],
  per_page_options: [30, 60, 100],
  default_per_page: 30,
  action_items: [],
  download_formats: [],
  pagination_total: true,
  ...extra,
})

export const resourceMetas: ResourceMeta[] = [
  resource('posts', 'Post', 'Posts', {
    menu_parent: 'Publishing',
    menu_priority: 5,
    actions: ['index', 'show', 'new', 'create', 'edit', 'update', 'destroy'],
    permissions: FULL,
    filters,
    scopes,
    default_scope: 'all',
    per_page_options: [10, 30, 60, 100],
    default_order: 'created_at_desc',
    batch_actions: batchActions,
    download_formats: ['csv'],
    action_items: postActionItems,
  }),
  resource('desks', 'Desk', 'Desks', { actions: ['index', 'show', 'new', 'create', 'edit', 'update'], permissions: { ...FULL, destroy: false } }),
  resource('payouts', 'Payout', 'Payouts', { menu_parent: 'Publishing', menu_priority: 7, permissions: { ...FULL, destroy: false } }),
  resource('syndicated_posts', 'Syndicated Post', 'Syndicated Posts', { menu_parent: 'Publishing', menu_priority: 8 }),
  resource('authors', 'Author', 'Authors', { menu_parent: 'Editorial', menu_priority: 1, permissions: READ_ONLY, download_formats: ['csv'] }),
  resource('content_approvals', 'Content Approval', 'Content Approvals', { menu_parent: 'Editorial', menu_priority: 4, permissions: READ_ONLY }),
  resource('teams', 'Team', 'Teams', { menu_parent: 'Editorial', menu_priority: 2 }),
  resource('attachments', 'Attachment', 'Attachments', { menu_parent: 'Editorial', menu_priority: 3, pagination_total: false, per_page_options: [10, 25, 50], default_per_page: 10 }),
  resource('users', 'User', 'Users', { menu_parent: 'Admin', menu_priority: 1, permissions: FULL }),
  resource('admin_policies', 'Admin Policy', 'Admin Policies', { menu_parent: 'Admin', menu_priority: 2 }),
  resource('editors', 'Editor', 'Editors'),
]

export const resourceSummaries: ResourceSummary[] = resourceMetas.map(
  ({ key, label, plural_label, menu_parent, menu_priority, actions, permissions }) => ({ key, label, plural_label, menu_parent, menu_priority, actions, permissions, meta_path: `/api/admin/${key}/_meta` }),
)

const leaf = (id: string, label: string): MenuItem => ({ id, label, resource: id, children: [] })

export const menu: MenuItem[] = [
  { id: 'dashboard', label: 'Dashboard', url: '/admin', priority: 1, children: [] },
  {
    id: 'publishing',
    label: 'Publishing',
    kind: 'group',
    icon: 'receipt',
    description: 'Posts and payouts waiting to go out.',
    priority: 5,
    children: [
      { ...leaf('posts', 'Posts'), description: 'Scheduled posts and their embargoes.' },
      { ...leaf('payouts', 'Payouts'), description: 'Author and advertiser payouts.' },
      leaf('syndicated_posts', 'Syndicated Posts'),
    ],
  },
  {
    id: 'editorial',
    label: 'Editorial',
    kind: 'group',
    icon: 'book-open',
    description: 'Authors, teams and the editorial records around them.',
    priority: 6,
    children: [
      { ...leaf('authors', 'Authors'), description: 'Every author, with their team and desk.' },
      { ...leaf('teams', 'Teams'), description: 'Who is responsible for which authors.' },
      leaf('attachments', 'Attachments'),
      { ...leaf('content_approvals', 'Content Approvals'), description: 'Approvals requested from editors before publishing.' },
    ],
  },
  {
    id: 'setup',
    label: 'Setup',
    kind: 'group',
    icon: 'sliders-horizontal',
    description: 'Reference data that other pages depend on.',
    priority: 8,
    children: [
      {
        id: 'setup/billing',
        label: 'Billing',
        kind: 'group',
        description: 'Plans, advertisers and the rates they pay.',
        children: [
          { ...leaf('billing_plans', 'Billing plans'), description: 'What each advertiser is charged for.' },
          leaf('advertisers', 'Advertisers'),
          leaf('rate_cards', 'Rate cards'),
        ],
      },
      { ...leaf('team_roles', 'Team roles'), description: 'Roles a team member can hold.' },
    ],
  },
  {
    id: 'admin',
    label: 'Admin',
    kind: 'group',
    icon: 'settings',
    description: 'Staff, permissions and batch tooling.',
    priority: 9,
    children: [leaf('users', 'Users'), leaf('admin_policies', 'Admin Policies'), { id: 'batch_operations', label: 'Batch Operations', page: 'batch_operations', children: [] }],
  },
]

export const utilityMenu: MenuItem[] = [
  { id: 'current_user', label: 'Dana Whitfield', url: '/admin/users/u-1', children: [] },
  { id: 'docs', label: 'Admin docs', url: 'https://docs.example.com/admin', children: [] },
  { id: 'logout', label: 'Logout', url: '/admin/logout', children: [] },
]

export const site: Site = {
  title: 'Acme Admin',
  title_link: '/admin',
  favicon: '/favicon.svg',
  home: null,
  logout: { url: '/admin/logout', method: 'delete' },
  utility_menu: utilityMenu,
  current_user: { id: 'u-1', display_name: 'Dana Whitfield' },
  locale: 'en',
  time_zone: 'America/New_York',
  date_format: null,
  datetime_format: null,
  footer: null,
  comments: false,
  default_per_page: 30,
  max_per_page: 100,
}

// Post 5004 is restricted: visible in the list but not openable.
export const rowPermissions = (e: Post): Permissions =>
  e.id === 5004 ? { show: false, update: false, destroy: false } : { show: true, update: true, destroy: true }

const liftEmbargo = (e: Post, placement: Action['placement']): Action => {
  const base = `/admin/posts/${e.id}`
  return {
    key: 'lift_embargo',
    label: 'Lift embargo',
    kind: 'member',
    placement,
    method: 'post',
    href: `${base}/lift_embargo`,
    api_path: `/api${base}/lift_embargo`,
    enabled: isEmbargoed(e),
    disabled_reason: isEmbargoed(e) ? null : "This post isn't embargoed",
  }
}

const retryPublication = (e: Post, placement: Action['placement']): Action => {
  const base = `/admin/posts/${e.id}`
  return { key: 'retry_publication', label: 'Retry publication', kind: 'member', placement, method: 'post', href: `${base}/retry_publication`, api_path: `/api${base}/retry_publication`, enabled: true }
}

export const postActions = (e: Post): Action[] => {
  const base = `/admin/posts/${e.id}`
  return [
    { key: 'edit', label: 'Edit', kind: 'edit', placement: 'header', method: 'get', href: `${base}/edit`, api_path: `/api${base}/edit`, enabled: true },
    retryPublication(e, 'header'),
    { key: 'reschedule_embargo', label: 'Reschedule embargo', kind: 'member', placement: 'header', method: 'get', href: `${base}/reschedule_embargo`, api_path: `/api${base}/reschedule_embargo`, form_path: `/api${base}/reschedule_embargo`, enabled: true },
    liftEmbargo(e, 'header'),
    {
      key: 'destroy',
      label: 'Delete',
      kind: 'destroy',
      placement: 'header',
      method: 'delete',
      href: base,
      api_path: `/api${base}`,
      confirm: `Delete post #${e.id}? This can't be undone.`,
      enabled: true,
    },
  ]
}

export const postRowActions = (e: Post): Action[] => [retryPublication(e, 'row'), liftEmbargo(e, 'row')]


// Deterministic v4-shaped ids so captures stay stable.
export const uuid = (n: number) => {
  const h = (k: number) => (Math.imul(n + 1, 2654435761) + k * 40503 >>> 0).toString(16).padStart(8, '0')
  return `${h(1)}-${h(2).slice(0, 4)}-4${h(3).slice(1, 4)}-a${h(4).slice(1, 4)}-${h(5)}${h(6).slice(0, 4)}`
}

