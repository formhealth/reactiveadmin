import type { FormField, FormResponse, FormSection, Option } from '@/api/generated/model'

const titleCase = (name: string) => name.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase())

const areas = ['comments', 'authors', 'tasks', 'users', 'billing_plans', 'admin_roles', 'admin_policies', 'teams', 'attachments']
const verbs = ['index', 'show', 'create', 'update', 'destroy']

// Every action string a policy can grant, labeled "Comments — index".
export const permissionPool: Option[] = [
  ...areas.flatMap((area) => [
    ...verbs.map((verb) => ({ label: `${titleCase(area)} — ${verb}`, value: `resources/${area}/${verb}`, hint: `resources/${area}/${verb}` })),
    { label: `${titleCase(area)} — * (all actions)`, value: `resources/${area}/*`, hint: `resources/${area}/*` },
  ]),
  ...['dashboard', 'reports'].map((page) => ({ label: `${titleCase(page)} — index`, value: `pages/${page}/index`, hint: `pages/${page}/index` })),
]

export const policyPool: Option[] = ['Team', 'Billing read-only', 'Scheduling admin', 'Support', 'Content reviewer', 'Enterprise ops', 'Superuser tools', 'Reporting'].map((label) => ({ label, value: label }))

export type NestedRow = { id: string; value: string; note?: string }

type Spec = {
  assoc: string
  title?: string
  attr: string
  label: string
  control: 'typeahead' | 'text'
  addLabel: string
  rows: NestedRow[]
  pool?: Option[]
  destroy?: boolean
  layout?: 'compact' | 'cards'
  withNote?: boolean
  hint?: string
  maxRows?: number
}

const hasMany = (resource: string, spec: Spec): FormSection => {
  const { assoc, attr, label, control, pool = [] } = spec
  const base = `${resource.replace(/s$/, '')}[${assoc}_attributes]`
  const field = (param: string, value: string | null): FormField[] => [
    {
      name: attr,
      label,
      control,
      required: false,
      param,
      value,
      hint: spec.hint,
      ...(control === 'typeahead' && { options: pool.filter((o) => o.value === value), options_path: `/api/admin/${resource}/_options?field=${assoc}.${attr}&context=form`, placeholder: `Search ${label.toLowerCase()}s…` }),
    },
  ]
  const note = (param: string, value?: string): FormField[] => (spec.withNote ? [{ name: 'note', label: 'Note', control: 'text', required: false, param, value: value ?? null }] : [])
  return {
    kind: 'has_many',
    title: spec.title,
    name: assoc,
    param_key: `${assoc}_attributes`,
    param: base,
    allow_destroy: spec.destroy ?? true,
    new_record_label: spec.addLabel,
    layout: spec.layout ?? 'compact',
    max_rows: spec.maxRows,
    fields: [],
    template_fields: [...field(`${base}[__INDEX__][${attr}]`, null), ...note(`${base}[__INDEX__][note]`)],
    records: spec.rows.map((row, i) => ({
      id: row.id,
      param: `${base}[${i}]`,
      destroy: spec.destroy ?? true,
      fields: [{ name: 'id', label: 'Id', control: 'hidden', required: false, param: `${base}[${i}][id]`, value: row.id }, ...field(`${base}[${i}][${attr}]`, row.value), ...note(`${base}[${i}][note]`, row.note)],
    })),
  }
}

const nameField = (resource: string, value: string): FormSection => ({
  kind: 'inputs',
  fields: [{ name: 'name', label: 'Name', control: 'text', required: true, param: `${resource.replace(/s$/, '')}[name]`, value }],
})

const form = (resource: string, id: string, name: string, spec: Spec): FormResponse => ({
  resource,
  id,
  title: `Edit ${name}`,
  display_name: name,
  action: { method: 'patch', path: `/api/admin/${resource}/${id}` },
  permissions: { show: true, update: true },
  form: { sections: [nameField(resource, name), hasMany(resource, spec)] },
})

export const ROLE_ID = 'role-1'
export const POLICY_ID = 'pol-1'
export const STALE_PERMISSION = 'resources/legacy_widgets/index'

const rolePolicies: NestedRow[] = ['Team', 'Scheduling admin', 'Support'].map((value, i) => ({ id: `rp-${i + 1}`, value }))

const policyPermissions: NestedRow[] = [
  'resources/comments/index',
  'resources/comments/show',
  'resources/authors/index',
  'resources/authors/show',
  'resources/authors/update',
  'resources/tasks/*',
  'resources/users/index',
  'pages/dashboard/index',
  STALE_PERMISSION,
  'resources/comments/index',
  'resources/billing_plans/show',
  'resources/admin_roles/index',
].map((value, i) => ({ id: `pp-${i + 1}`, value }))

export const STALE_ROW_ID = 'pp-9'

const permissions = (overrides: Partial<Spec> = {}): Spec => ({
  assoc: 'admin_policy_permissions',
  title: 'Permissions',
  attr: 'action',
  label: 'Permission',
  control: 'typeahead',
  addLabel: 'Add permission',
  pool: permissionPool,
  rows: policyPermissions,
  ...overrides,
})

export const roleForm = () =>
  form('admin_roles', ROLE_ID, 'Desk coordinator', {
    assoc: 'admin_policy_roles',
    title: 'Policies',
    attr: 'admin_policy_name',
    label: 'Admin policy',
    control: 'typeahead',
    addLabel: 'Add admin policy',
    pool: policyPool,
    rows: rolePolicies,
  })

export const policyForm = (overrides?: Partial<Spec>) => form('admin_policies', POLICY_ID, 'Team', permissions(overrides))

export const textPolicyForm = () => policyForm({ control: 'text', pool: [], rows: policyPermissions.slice(0, 4), hint: 'Like resources/<name>/<action>, or * for every action' })

export const cardsPolicyForm = () => policyForm({ withNote: true, layout: 'cards', rows: policyPermissions.slice(0, 3).map((r, i) => ({ ...r, note: ['Read only', '', 'Temporary until Q4'][i] })) })
