import { Suspense, type ReactNode } from 'react'
import type { RouteObject } from 'react-router'
import { RouteBoundary } from '@/boundaries/RouteBoundary'
import { Layout } from '@/components/Layout'
import { RouteSkeleton } from '@/components/RouteSkeleton'
import { Home } from '@/pages/Home'
import { NotFound } from '@/pages/NotFound'
import { ActionPage, GroupOverview, ResourceForm, ResourceOrPage, ResourceShow } from '@/pages/lazy'

// Layout stays mounted when a page fails or loads, so the menu still works.
const guarded = (element: ReactNode) => (
  <RouteBoundary>
    <Suspense fallback={<RouteSkeleton />}>{element}</Suspense>
  </RouteBoundary>
)

// A data router (not <Routes>) because `useBlocker` guards unsaved edits.
export const routes: RouteObject[] = [
  {
    element: <Layout />,
    children: [
      { index: true, element: guarded(<Home />) },
      { path: 'groups/*', element: guarded(<GroupOverview />) },
      { path: ':resource', element: guarded(<ResourceOrPage />) },
      { path: ':resource/new', element: guarded(<ResourceForm mode="new" />) },
      { path: ':resource/actions/:key', element: guarded(<ActionPage />) },
      { path: ':resource/:id', element: guarded(<ResourceShow />) },
      { path: ':resource/:id/edit', element: guarded(<ResourceForm mode="edit" />) },
      { path: ':resource/:id/actions/:key', element: guarded(<ActionPage />) },
      { path: '*', element: guarded(<NotFound />) },
    ],
  },
]
