import { useState } from 'react'
import type { Meta, StoryObj } from '@storybook/react-vite'
import { expect, userEvent, within } from 'storybook/test'
import type { Filter } from '@/api/generated/model'
import type { Query } from '@/lib/list'
import { filters as postFilters } from '@/mocks/fixtures'
import { FilterBar } from './FilterBar'

const byName = (name: string) => postFilters.find((f) => f.name === name)!

const numberFilter: Filter = {
  name: 'views',
  label: 'Views',
  control: 'number',
  predicates: [
    { param: 'views_gteq', label: 'Greater or equal' },
    { param: 'views_lteq', label: 'Less or equal' },
  ],
}

const booleanFilter: Filter = { name: 'seo_checked', label: 'SEO Checked', control: 'boolean', param: 'seo_checked_eq' }

type Q = Query

function Bar({ filters, initial = {} }: { filters: Filter[]; initial?: Q }) {
  const [q, setQ] = useState<Q>(initial)
  return (
    <FilterBar
      filters={filters}
      q={q}
      setQ={(changes) => setQ((prev) => Object.fromEntries(Object.entries({ ...prev, ...changes }).filter(([, v]) => v?.length)) as Q)}
      clearAll={() => setQ({})}
    />
  )
}

const meta = {
  title: 'Filters',
  component: Bar,
  parameters: { viewportSize: { width: 960, height: 160 } },
} satisfies Meta<typeof Bar>

export default meta
type Story = StoryObj<typeof meta>

const open = { viewportSize: { width: 960, height: 520 } }

export const Text: Story = { args: { filters: [byName('author_id')], initial: { author_id_gteq: '110' } } }

export const NumberWithPredicates: Story = { args: { filters: [numberFilter], initial: { views_lteq: '12' } } }

export const Select: Story = { args: { filters: [byName('publication_status')], initial: { publication_status_eq: 'rejected' } } }

export const Boolean: Story = { args: { filters: [booleanFilter], initial: { seo_checked_eq: 'true' } } }

export const TypeaheadClosed: Story = { args: { filters: [byName('editor')], initial: { editor_id_eq: '2' } } }

export const TypeaheadOpen: Story = {
  args: { filters: [byName('editor')] },
  parameters: open,
  play: async ({ canvasElement }) => {
    await userEvent.click(within(canvasElement).getByRole('combobox', { name: 'Editor' }))
    await expect(await within(document.body).findByPlaceholderText(/search editor/i)).toBeVisible()
  },
}

export const DateRangeClosed: Story = {
  args: { filters: [byName('published_on')], initial: { published_on_gteq: '2026-10-01', published_on_lteq: '2026-10-14' } },
}

export const DateRangePresetsOpen: Story = {
  args: { filters: [byName('published_on')] },
  parameters: open,
  play: async ({ canvasElement }) => {
    await userEvent.click(within(canvasElement).getByRole('button', { name: /Published On/ }))
    await expect(await within(document.body).findByRole('button', { name: 'Last 7 days' })).toBeVisible()
  },
}

export const ActiveFilterChips: Story = {
  args: {
    filters: [byName('author_id'), byName('editor'), byName('publication_status'), byName('published_on'), numberFilter, booleanFilter],
    initial: {
      author_id_eq: '104',
      editor_id_eq: '3',
      publication_status_eq: 'review_failed',
      published_on_gteq: '2026-09-16',
      published_on_lteq: '2026-10-16',
      views_gteq: '2',
      seo_checked_eq: 'false',
    },
  },
  parameters: { viewportSize: { width: 960, height: 220 } },
}

const weightFilter: Filter = {
  name: 'weight',
  label: 'Weight',
  control: 'checkboxes',
  multiple: true,
  param: 'weight_in',
  options: [1, 2, 3].map((n) => ({ label: `Weight ${n}`, value: String(n) })),
}

export const CheckboxesMultiple: Story = {
  args: { filters: [weightFilter], initial: { weight_in: ['1', '2'] } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(canvas.getByRole('button', { name: 'Weight 1' })).toHaveAttribute('aria-pressed', 'true')
    await expect(canvas.getByRole('button', { name: 'Weight 3' })).toHaveAttribute('aria-pressed', 'false')
    await userEvent.click(canvas.getByRole('button', { name: 'Weight 3' }))
    await expect(canvas.getByRole('button', { name: 'Remove Weight: Weight 1, Weight 2, Weight 3' })).toBeVisible()
    await userEvent.click(canvas.getByRole('button', { name: 'Weight 1' }))
    await expect(canvas.getByRole('button', { name: 'Weight 1' })).toHaveAttribute('aria-pressed', 'false')
    await expect(canvas.getByRole('button', { name: 'Remove Weight: Weight 2, Weight 3' })).toBeVisible()
    await userEvent.click(canvas.getByRole('button', { name: 'Remove Weight: Weight 2, Weight 3' }))
    await expect(canvas.queryByRole('button', { name: /^Remove/ })).toBeNull()
    await expect(canvas.getByRole('button', { name: 'Weight 2' })).toHaveAttribute('aria-pressed', 'false')
  },
}

export const AllControls: Story = {
  args: { filters: [...postFilters, numberFilter, booleanFilter] },
  parameters: { viewportSize: { width: 960, height: 200 } },
}
