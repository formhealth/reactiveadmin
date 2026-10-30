import { useParams } from 'react-router'
import { RouteSkeleton } from '@/components/RouteSkeleton'
import { useManifest } from '@/hooks/useManifest'
import { PageView, ResourceIndex } from './lazy'

// A classic admin has one URL shape for both: `/admin/authors` is a resource and `/admin/dashboard` a page, so the
// manifest tells them apart. Anything the manifest doesn't list as a resource is asked for as a page, which answers
// not found for a name that is neither.
export function ResourceOrPage() {
  const { resource = '' } = useParams()
  const { data, isPending } = useManifest()
  if (isPending) return <RouteSkeleton />
  return !data || data.resources.some((r) => r.key === resource) ? <ResourceIndex /> : <PageView page={resource} />
}
