import { useEffect } from 'react'
import { recordVisit } from '@/lib/recent'

// Remembers a record once its page has loaded, for the command palette's "Recent records".
export function useRecordVisit(loaded: boolean, resource: string, id: string) {
  useEffect(() => {
    if (loaded && resource && id) recordVisit({ resource, id })
  }, [loaded, resource, id])
}
