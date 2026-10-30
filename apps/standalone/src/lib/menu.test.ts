import { describe, expect, it } from 'vitest'
import type { MenuItem } from '@/api/generated/model'
import { findGroup, fullPath, groupRoute, hereOf, isGroup, menuGroups, menuLeaves, menuRoute, searchMenu, trailTo } from './menu'

const leaf = (id: string, label: string, description?: string): MenuItem => ({ id, label, resource: id, description, children: [] })

const menu: MenuItem[] = [
  { id: 'dashboard', label: 'Dashboard', url: '/admin', children: [] },
  {
    id: 'setup',
    label: 'Setup',
    kind: 'group',
    children: [
      { id: 'setup/billing', label: 'Billing', kind: 'group', description: 'Plans and rates', children: [leaf('billing_plans', 'Billing plans'), leaf('rate_cards', 'Rate cards')] },
      leaf('roles', 'Team roles'),
    ],
  },
  { id: 'empty', label: 'Empty', kind: 'group', children: [] },
]

describe('menu groups', () => {
  it('lists every non-empty group with the path above it', () => {
    expect(menuGroups(menu).map((g) => [g.id, fullPath(g)])).toEqual([
      ['setup', 'Setup'],
      ['setup/billing', 'Setup / Billing'],
    ])
  })

  it('finds a group and its ancestors by id', () => {
    const found = findGroup(menu, 'setup/billing')
    expect(found?.group.label).toBe('Billing')
    expect(found?.path.map((g) => g.id)).toEqual(['setup'])
    expect(findGroup(menu, 'billing_plans')).toBeUndefined()
  })

  it('treats an item with children, or kind group, as a group', () => {
    expect(isGroup(menu[1])).toBe(true)
    expect(isGroup(menu[0])).toBe(false)
  })
})

describe('searchMenu', () => {
  it('matches the full path, so a parent word finds its children', () => {
    expect(searchMenu(menu, 'setup billing rate').leaves.map(fullPath)).toEqual(['Setup / Billing / Rate cards'])
  })

  it('also matches descriptions and returns groups separately', () => {
    const { leaves, groups } = searchMenu(menu, 'plans')
    expect(leaves.map((l) => l.id)).toEqual(['billing_plans'])
    expect(groups.map((g) => g.id)).toEqual(['setup/billing'])
  })

  it('keeps leaves in menu order', () => {
    expect(menuLeaves(menu).map((l) => l.id)).toEqual(['dashboard', 'billing_plans', 'rate_cards', 'roles'])
  })
})

describe('routes', () => {
  it('routes a group to its overview page and recognises it as the current place', () => {
    expect(groupRoute('setup/billing')).toBe('/groups/setup/billing')
    expect(hereOf('/groups/setup/billing')).toEqual({ group: 'setup/billing' })
    expect(trailTo(menu, hereOf('/groups/setup/billing'))).toEqual(['setup', 'setup/billing'])
    expect(trailTo(menu, hereOf('/rate_cards'))).toEqual(['setup', 'setup/billing', 'rate_cards'])
  })
})

describe('menuRoute', () => {
  const mapUrl = (url: string) => url.replace('/admin', '')

  it('routes resources, pages and mappable classic URLs', () => {
    expect(menuRoute({ resource: 'authors' }, mapUrl)).toBe('/authors')
    expect(menuRoute({ page: 'ops' }, mapUrl)).toBe('/ops')
    expect(menuRoute({ url: '/admin/billing' }, mapUrl)).toBe('/billing')
  })

  it('leaves a classic-only item as a link out, though it still names its resource', () => {
    expect(menuRoute({ resource: 'staff', url: '/admin/staff', api_denied: true }, mapUrl)).toBeUndefined()
    expect(menuRoute({ page: 'back_office', url: '/admin/back_office', api_denied: true }, mapUrl)).toBeUndefined()
  })
})
