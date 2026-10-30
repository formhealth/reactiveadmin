import { lazy } from 'react'

// One chunk per page; the shell and the menu load without any of them.
export const ActionPage = lazy(() => import('@/pages/ActionPage').then((m) => ({ default: m.ActionPage })))
export const GroupOverview = lazy(() => import('@/pages/GroupOverview').then((m) => ({ default: m.GroupOverview })))
export const PageView = lazy(() => import('@/pages/PageView').then((m) => ({ default: m.PageView })))
export const ResourceForm = lazy(() => import('@/pages/ResourceForm').then((m) => ({ default: m.ResourceForm })))
export const ResourceIndex = lazy(() => import('@/pages/ResourceIndex').then((m) => ({ default: m.ResourceIndex })))
export const ResourceOrPage = lazy(() => import('@/pages/ResourceOrPage').then((m) => ({ default: m.ResourceOrPage })))
export const ResourceShow = lazy(() => import('@/pages/ResourceShow').then((m) => ({ default: m.ResourceShow })))
