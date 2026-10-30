import { getGetLabelsQueryOptions } from '@/api/generated/core'
import type { LabelsResponse } from '@/api/generated/model'
import type { Recent } from '@/lib/recent'

type Pointer = Pick<Recent, 'resource' | 'id'>

// One display-name lookup per resource: recents never fetch the records themselves.
export const labelGroups = (recents: Pointer[]) =>
  Object.entries(Object.groupBy(recents, (r) => r.resource)).map(([resource, group = []]) => ({ resource, ids: group.map((r) => r.id) }))

export const labelQueryOptions = ({ resource, ids }: ReturnType<typeof labelGroups>[number]) =>
  getGetLabelsQueryOptions(resource, { ids }, { query: { staleTime: 60_000, retry: false } })

export const labelsByKey = (responses: (LabelsResponse | undefined)[]) =>
  new Map(responses.flatMap((r) => r?.labels ?? []).map((l) => [`${l.resource}/${l.id}`, l.display_name]))
