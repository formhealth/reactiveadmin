import type { Meta, StoryObj } from '@storybook/react-vite'
import { http, HttpResponse } from 'msw'
import { expect, screen, userEvent, within } from 'storybook/test'
import type { Action, FormResponse, ResourceMeta, ShowResponse } from '@/api/generated/model'
import { postActions, postName, posts, resourceMetas, resourceSummaries, rowPermissions, showLayout } from '@/mocks/fixtures'
import { deskForm, desks } from '@/mocks/forms'
import { manifestBody } from '@/mocks/handlers'
import { ResourceForm } from './ResourceForm'
import { ResourceIndex } from './ResourceIndex'
import { ResourceShow } from './ResourceShow'

const REASON = 'Billing runs are started in the classic admin'
const [post] = posts
const [desk] = desks

const classic = (key: string, label: string, kind: Action['kind'], href: string, extra: Partial<Action> = {}): Action => ({
  key,
  label,
  kind,
  placement: 'header',
  method: 'post',
  href,
  supported: false,
  api_denied: true,
  classic_url: href,
  disabled_reason: REASON,
  enabled: true,
  ...extra,
})

const postMeta = resourceMetas.find((r) => r.key === 'posts')!
const manifestWith = (api_denied: NonNullable<(typeof resourceSummaries)[number]['api_denied']>) =>
  http.get('/api/admin/_manifest', () =>
    HttpResponse.json({ ...manifestBody, resources: resourceSummaries.map((r) => (r.key === 'posts' ? { ...r, api_denied } : r)) }),
  )
const metaWith = (changes: Partial<ResourceMeta>) => http.get('/api/admin/posts/_meta', () => HttpResponse.json({ ...postMeta, ...changes }))

const meta = {
  title: 'Pages/ApiDenied',
  component: ResourceIndex,
  parameters: { routePath: ':resource', route: '/posts', viewportSize: { width: 1440, height: 900 } },
} satisfies Meta<typeof ResourceIndex>

export default meta
type Story = StoryObj<typeof meta>

const reservedIndex = {
  msw: {
    handlers: [
      manifestWith({ actions: ['new', 'create', 'edit', 'update'], classic_url: '/admin/posts' }),
      metaWith({
        api_denied: { actions: ['new', 'create', 'edit', 'update'], classic_url: '/admin/posts' },
        action_items: [
          ...postMeta.action_items!,
          classic('sweep', 'Sweep embargoes', 'collection', '/admin/posts', { disabled_reason: REASON }),
        ],
        batch_actions: [
          ...postMeta.batch_actions!,
          { key: 'bill_now', label: 'Bill now', inputs: [], api_denied: true, classic_url: '/admin/posts', disabled_reason: REASON },
        ],
      }),
    ],
  },
}

export const IndexHeader: Story = {
  parameters: reservedIndex,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    const add = await canvas.findByRole('link', { name: /New Post/ })
    await expect(add).toHaveAttribute('href', '/admin/posts/new?classic=1')
    await expect(add).toHaveAttribute('target', '_blank')
    await expect(add).toHaveAttribute('rel', expect.stringContaining('noopener'))
    await expect(await canvas.findByRole('link', { name: /Sweep embargoes/ })).toHaveAttribute('target', '_blank')
  },
}

export const IndexHeaderDark: Story = { ...IndexHeader, globals: { theme: 'dark' } }

export const BatchActionLink: Story = {
  parameters: reservedIndex,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await userEvent.click(await canvas.findByRole('checkbox', { name: 'Select record 5000' }))
    const bar = within(await canvas.findByRole('region', { name: 'Batch actions' }))
    await expect(await bar.findByRole('link', { name: /Bill now/ })).toHaveAttribute('href', '/admin/posts?classic=1')
    await expect(bar.queryByRole('button', { name: 'Bill now' })).toBeNull()
  },
}

export const RowMenuClassicView: Story = {
  parameters: { msw: { handlers: [manifestWith({ actions: ['show'], classic_url: '/admin/posts' })] } },
  play: async ({ canvasElement }) => {
    await userEvent.click((await within(canvasElement).findAllByRole('button', { name: /Actions for / }))[0])
    const view = await screen.findByRole('menuitem', { name: /View/ })
    await expect(view.getAttribute('href')).toMatch(/^\/admin\/posts\/\d+\?classic=1$/)
    await expect(view).toHaveAttribute('target', '_blank')
  },
}

const show = (actions: Action[]): ShowResponse => ({
  resource: 'posts',
  id: String(post.id),
  title: `Post #${post.id}`,
  display_name: postName(post),
  permissions: rowPermissions(post),
  actions,
  layout: showLayout(post),
})

const reservedShow = () => {
  const base = `/admin/posts/${post.id}`
  const actions = postActions(post).map((action) =>
    action.key === 'destroy' ? classic('destroy', 'Delete', 'destroy', base, { method: 'delete', placement: 'header' }) : action,
  )
  return http.get(`/api/admin/posts/${post.id}`, () =>
    HttpResponse.json(show([...actions, classic('impersonate', 'Impersonate', 'member', base, { disabled_reason: 'Impersonation is only allowed from the classic admin' })])),
  )
}

export const ShowActions: Story = {
  parameters: { routePath: ':resource/:id', route: `/posts/${post.id}`, msw: { handlers: [reservedShow()] } },
  render: () => <ResourceShow />,
  play: async ({ canvasElement }) => {
    const link = await within(canvasElement).findByRole('link', { name: /Impersonate/ })
    await expect(link).toHaveAttribute('href', `/admin/posts/${post.id}?classic=1`)
    await expect(link).toHaveAttribute('target', '_blank')
    await expect(within(canvasElement).queryByRole('button', { name: 'Impersonate' })).toBeNull()
  },
}

export const ShowActionsDark: Story = { ...ShowActions, globals: { theme: 'dark' } }

export const ShowMenuClassicDelete: Story = {
  parameters: ShowActions.parameters,
  render: () => <ResourceShow />,
  play: async ({ canvasElement }) => {
    await userEvent.click(await within(canvasElement).findByRole('button', { name: 'More actions' }))
    const item = await screen.findByRole('menuitem', { name: /Delete/ })
    await expect(item).toHaveAttribute('target', '_blank')
    await expect(item).toHaveTextContent(REASON)
  },
}

export const Refused: Story = {
  parameters: {
    routePath: ':resource/:id',
    route: `/posts/${post.id}`,
    msw: {
      handlers: [
        http.get(`/api/admin/posts/${post.id}`, () =>
          HttpResponse.json(
            { code: 'api_denied', message: 'Impersonation is only allowed from the classic admin', classic_url: `/admin/posts/${post.id}/impersonate` },
            { status: 403 },
          ),
        ),
      ],
    },
    viewportSize: { width: 1440, height: 520 },
  },
  render: () => <ResourceShow />,
  play: async ({ canvasElement }) => {
    const link = await within(canvasElement).findByRole('link', { name: /Open in classic admin/ })
    await expect(link).toHaveAttribute('href', `/admin/posts/${post.id}/impersonate?classic=1`)
    await expect(link).toHaveAttribute('target', '_blank')
  },
}

export const RefusedDark: Story = { ...Refused, globals: { theme: 'dark' } }

const reservedForm = (): FormResponse => {
  const form = deskForm(desk)
  const [first, ...rest] = form.form.sections
  const [name, ...others] = first.fields ?? []
  return {
    ...form,
    form: {
      sections: [{ ...first, fields: [{ ...name, disabled: true, api_denied: true, classic_url: `/admin/desks/${desk.id}/edit` }, ...others] }, ...rest],
    },
  }
}

export const FormField: Story = {
  parameters: {
    routePath: ':resource/:id/edit',
    route: `/desks/${desk.id}/edit`,
    msw: { handlers: [http.get(`/api/admin/desks/${desk.id}/edit`, () => HttpResponse.json(reservedForm()))] },
    viewportSize: { width: 1280, height: 900 },
  },
  render: () => <ResourceForm mode="edit" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement)
    await expect(await canvas.findByRole('textbox', { name: /^Name/ })).toBeDisabled()
    const link = await canvas.findByRole('link', { name: /Open in classic admin/ })
    await expect(link).toHaveAttribute('href', `/admin/desks/${desk.id}/edit?classic=1`)
    await expect(link).toHaveAttribute('target', '_blank')
  },
}

export const FormFieldDark: Story = { ...FormField, globals: { theme: 'dark' } }
