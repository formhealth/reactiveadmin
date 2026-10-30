import type { Action, Column, Row } from '@/api/generated/model'
import { day, uuid } from './fixtures'

const authorNames = ['Alex Nguyen', 'Jordan Patel', 'Sam Garcia', 'Taylor Johnson', 'Morgan Kim', 'Casey Rossi', 'Riley Haddad', 'Jamie Murphy']

export const authorColumns: Column[] = [
  ['id', 'ID'],
  ['name', 'Name'],
  ['external_id', 'External ID'],
  ['state', 'State'],
  ['status', 'Status'],
  ['created_at', 'Created at'],
].map(([key, label]) => ({ key, label, sortable: key !== 'status' }))

// Frame (page and dialog), iframe and external ladder rungs, all on one record.
export const authorActions = (id: string, placement: Action['placement']): Action[] => {
  const base = `/admin/authors/${id}`
  return [
    {
      key: 'team_history',
      label: 'Team history',
      kind: 'member',
      placement,
      method: 'get',
      href: `${base}/team_history`,
      view: { mode: 'frame', path: `${base}/team_history`, presentation: 'page' },
      enabled: true,
    },
    {
      key: 'add_team_member',
      label: 'New team member',
      kind: 'member',
      placement,
      method: 'get',
      href: `${base}/team_members/new`,
      view: { mode: 'frame', path: `${base}/team_members/new`, presentation: 'dialog' },
      enabled: true,
    },
    {
      key: 'preview_schedule',
      label: 'Preview schedule',
      kind: 'member',
      placement,
      method: 'get',
      href: `${base}/preview_schedule`,
      view: { mode: 'iframe', path: '/admin/preview_schedule.html?embed=1', presentation: 'page' },
      enabled: true,
    },
    { key: 'open_in_cms', label: 'Open in CMS', kind: 'link', placement, method: 'get', external: true, href: 'https://cms.example.com/authors/48210', enabled: true },
  ]
}

export const authorRows: Row[] = authorNames.map((name, i) => ({
  id: uuid(i),
  display_name: name,
  permissions: { show: true, update: false, destroy: false },
  actions: authorActions(uuid(i), 'row').slice(0, 1),
  cells: {
    id: { type: 'text', text: uuid(i) },
    name: { type: 'text', text: name },
    external_id: { type: 'text', text: `EXT-${48210 + i * 7}` },
    state: { type: 'text', text: ['CA', 'NY', 'TX', 'WA'][i % 4] },
    status: { type: 'status', label: i % 3 === 0 ? 'Onboarding' : 'Active', variant: i % 3 === 0 ? 'info' : 'success' },
    created_at: { type: 'datetime', value: day(-(i * 9) - 3).replace(/T.*/, 'T14:20:00.000Z') },
  },
}))

export const authorIndex = (id: string) => Math.max(0, authorRows.findIndex((r) => r.id === id))
