import { lazy, Suspense, type ComponentProps } from 'react'
import type { FormDialog } from './FormDialog'

// Dialogs open on a click, so the form stack (rhf, zod, pickers, nodes) loads on demand rather than with the page.
const Form = lazy(() => import('./FormDialog').then((m) => ({ default: m.FormDialog })))
const Overlay = lazy(() => import('@/views/ActionView').then((m) => ({ default: m.ActionViewOverlay })))

export function LazyFormDialog<T>(props: ComponentProps<typeof FormDialog<T>>) {
  return (
    <Suspense>
      <Form {...(props as ComponentProps<typeof Form>)} />
    </Suspense>
  )
}

export function LazyActionViewOverlay(props: ComponentProps<typeof Overlay>) {
  return (
    <Suspense>
      <Overlay {...props} />
    </Suspense>
  )
}
