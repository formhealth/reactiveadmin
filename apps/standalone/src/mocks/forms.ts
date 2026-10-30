import type { Column, FormField, FormResponse, Option, Row, Session } from '@/api/generated/model'
import { postName, editors, type Post } from './fixtures'
import { permissionPool, policyPool } from './nested'

export const CSRF_TOKEN = 'mock-csrf-token'

export const session: Session = { user: { id: 'u-1', display_name: 'Dana Whitfield' }, csrf_token: CSRF_TOKEN }

const editorPool = [
  ...editors,
  ...['Amara Osei', 'Benedict Lowe', 'Camila Duarte', 'Daniel Ferreira', 'Elena Petrov', 'Farid Haddad', 'Greta Lindqvist', 'Hiro Tanaka', 'Imani Brooks', 'Julian Moreau', 'Kavya Menon', 'Leonard Voss', 'Mei Zhang', 'Nadia Karim', 'Omar Siddiqui', 'Paula Ricci'].map(
    (n) => `${n}`,
  ),
]

const staff: Option[] = [
  { label: 'Sarah Chen', value: 'sarah.chen@example.com' },
  { label: 'Scenario Editor', value: 'sam.reyes@example.com' },
  { label: 'Rita Dawson', value: 'rita.dawson@example.com' },
  { label: 'Lauren Thompson', value: 'lauren.thompson@example.com' },
  { label: 'Marcus Johnson', value: 'marcus.johnson@example.com' },
]

const surnames = ['Nguyen', 'Okafor', 'Lindqvist', 'Haddad', 'Moreau', 'Tanaka', 'Brooks', 'Duarte', 'Petrov', 'Menon', 'Voss', 'Zhang']
const givens = ['Alex', 'Jordan', 'Sam', 'Riley', 'Casey', 'Morgan', 'Taylor']

// Enough authors that a search is truncated and pages; ids are integers, so a pasted id resolves too.
export const authorPool: Option[] = Array.from({ length: 84 }, (_, i) => {
  const given = givens[i % givens.length]
  const surname = surnames[(i * 5) % surnames.length]
  return { label: `${given} ${surname}`, value: String(100 + i), hint: `${given.toLowerCase()}.${surname.toLowerCase()}${i}@example.com` }
})

export const optionPools: Record<string, Option[]> = {
  editor: editorPool.map((label, i) => ({ label, value: String(i + 1), hint: `ID ${1003000000 + i * 7919}` })),
  lead_editor_email: staff.map((o) => ({ ...o, hint: o.value })),
  'desk_members.user_email': staff.map((o) => ({ ...o, hint: o.value })),
  author: authorPool,
  'admin_policy_permissions.action': permissionPool,
  'admin_policy_roles.admin_policy_name': policyPool,
}

const field = (f: Partial<FormField> & Pick<FormField, 'name' | 'label' | 'control'>, param: string): FormField => ({ required: false, value: null, ...f, param })

const seoOf = (e: Post) => ({
  publisher: 'Acme Media',
  reader_id: `XYZ${e.author_id}00${e.id}`,
  indexing: { active: e.seo_checked, price_cents: 3500 },
  plans: [{ code: 'WEB-1', primary: true }],
})

const detailsOf = (e: Post) => ({
  author_first_name: e.author.split(' ')[0],
  author_last_name: e.author.split(' ')[1],
  author_state: 'MA',
  tags: ['news'],
  rendering_provider_npi: '1234567890',
})

export const postForm = (e?: Post): FormResponse => {
  const param = (name: string) => `post[${name}]`
  return {
    resource: 'posts',
    id: e && String(e.id),
    title: e ? `Edit Post #${e.id}` : 'New Post',
    display_name: e && postName(e),
    actions: e ? [{ key: 'view', label: 'View', kind: 'link', placement: 'header', method: 'get', href: `/admin/posts/${e.id}`, enabled: true }] : [],
    action: { method: e ? 'patch' : 'post', path: `/api/admin/posts${e ? `/${e.id}` : ''}` },
    permissions: e ? { show: true, update: true } : { create: true },
    form: {
      sections: [
        {
          title: 'Basic Information',
          kind: 'inputs',
          fields: [
            field(
              {
                name: 'editor',
                label: 'Editor',
                control: 'typeahead',
                required: true,
                value: e && String(e.editor_id),
                options: e ? [{ label: editorPool[e.editor_id - 1], value: String(e.editor_id) }] : [],
                options_path: `/api/admin/posts/_options?field=editor&context=form${e ? `&id=${e.id}` : ''}`,
                placeholder: 'Search editors…',
              },
              param('editor_id'),
            ),
            field(
              {
                name: 'author',
                label: 'Author',
                control: 'typeahead',
                value: e && String(e.author_id),
                options: [],
                options_path: `/api/admin/posts/_options?field=author&context=form${e ? `&id=${e.id}` : ''}`,
                placeholder: 'Search authors…',
                hint: 'Search by name, or paste an author id',
              },
              param('author_id'),
            ),
            field({ name: 'published_on', label: 'Published on', control: 'date', required: true, value: e?.published_on }, param('published_on')),
            field({ name: 'webhook_secret', label: 'Webhook secret', control: 'text', masked: true, hint: 'Leave blank to keep the current secret' }, param('webhook_secret')),
            field(
              {
                name: 'embargo_until',
                label: 'Embargo until',
                control: 'date',
                value: e?.embargo_until,
                hint: 'Post will be published on this date (embargoed through the day before)',
              },
              param('embargo_until'),
            ),
          ],
        },
        {
          title: 'Details (JSON) - values are generated during import',
          kind: 'inputs',
          fields: [field({ name: 'details', label: 'Details', control: 'json', value: e ? detailsOf(e) : null, hint: 'Enter valid JSON', input_html: { rows: 9 } }, param('details'))],
        },
        {
          title: 'SEO Data (JSON) - values are pulled from the CMS. Use the SEO refresh button first.',
          kind: 'inputs',
          fields: [field({ name: 'seo_data', label: 'SEO data', control: 'json', value: e ? seoOf(e) : null, hint: 'Enter valid JSON', input_html: { rows: 8 } }, param('seo_data'))],
        },
      ],
    },
  }
}

export const rescheduleForm = (e: Post): FormResponse => ({
  resource: 'posts',
  id: String(e.id),
  title: `Reschedule embargo for #${e.id}`,
  action: { method: 'post', path: `/api/admin/posts/${e.id}/reschedule_embargo` },
  permissions: { update: true },
  form: {
    sections: [
      {
        kind: 'inputs',
        fields: [field({ name: 'embargo_until', label: 'Embargo until', control: 'date', required: true, value: e.embargo_until, hint: 'Post will be released on this date.' }, 'embargo_until')],
      },
    ],
  },
})

export type Desk = { id: string; name: string; region_id: string; lead_editor_email: string | null; members: { id: string; email: string }[] }

const regions: Option[] = ['Region 1', 'Region 2', 'Region 3', 'Region 4'].map((label, i) => ({ label, value: `region-${i + 1}` }))

export const desks: Desk[] = [
  { id: 'desk-1', name: 'Features desk', region_id: 'region-1', lead_editor_email: 'sarah.chen@example.com', members: [{ id: 'pu-1', email: 'rita.dawson@example.com' }, { id: 'pu-2', email: 'marcus.johnson@example.com' }] },
  { id: 'desk-2', name: 'Opinion desk', region_id: 'region-3', lead_editor_email: null, members: [] },
]

const BASE = 'desk[desk_members_attributes]'

export const deskForm = (desk?: Desk): FormResponse => {
  const userEmail = (param: string, value: string | null) =>
    field(
      {
        name: 'user_email',
        label: 'User',
        control: 'typeahead',
        free_text: true,
        value,
        options: staff.filter((o) => o.value === value),
        options_path: '/api/admin/desks/_options?field=desk_members.user_email&context=form',
      },
      param,
    )
  return {
    resource: 'desks',
    id: desk?.id,
    title: desk ? `Edit desk: ${desk.name}` : 'New desk',
    action: { method: desk ? 'patch' : 'post', path: `/api/admin/desks${desk ? `/${desk.id}` : ''}` },
    permissions: { create: true, update: true },
    form: {
      sections: [
        {
          kind: 'inputs',
          fields: [
            field({ name: 'name', label: 'Name', control: 'text', required: true, value: desk?.name }, 'desk[name]'),
            field({ name: 'region', label: 'Region', control: 'select', required: true, value: desk?.region_id, options: regions }, 'desk[region_id]'),
            field(
              {
                name: 'lead_editor_email',
                label: 'Lead editor email',
                control: 'typeahead',
                free_text: true,
                value: desk?.lead_editor_email,
                options: staff.filter((o) => o.value === desk?.lead_editor_email),
                options_path: '/api/admin/desks/_options?field=lead_editor_email&context=form',
              },
              'desk[lead_editor_email]',
            ),
          ],
        },
        {
          kind: 'has_many',
          title: 'Members',
          name: 'desk_members',
          param_key: 'desk_members_attributes',
          param: BASE,
          allow_destroy: true,
          new_record_label: 'Add member',
          fields: [],
          template_fields: [userEmail(`${BASE}[__INDEX__][user_email]`, null)],
          records: (desk?.members ?? []).map((m, i) => ({
            id: m.id,
            param: `${BASE}[${i}]`,
            destroy: true,
            fields: [field({ name: 'id', label: 'Id', control: 'hidden', value: m.id }, `${BASE}[${i}][id]`), userEmail(`${BASE}[${i}][user_email]`, m.email)],
          })),
        },
      ],
    },
  }
}

export const deskColumns: Column[] = [
  { key: 'name', label: 'Name', sortable: true },
  { key: 'region', label: 'Region', sortable: false },
  { key: 'members', label: 'Members', sortable: false },
]

export const deskRows: Row[] = desks.map((p) => ({
  id: p.id,
  permissions: { show: false, update: true, destroy: false },
  cells: {
    name: { type: 'text', text: p.name },
    region: { type: 'text', text: regions.find((r) => r.value === p.region_id)?.label ?? '' },
    members: { type: 'text', text: String(p.members.length) },
  },
}))
