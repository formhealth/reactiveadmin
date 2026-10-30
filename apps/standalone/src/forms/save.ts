import { apiFetch } from '@/api/fetcher'
import type { FormLock, FormResponse, WriteResult } from '@/api/generated/model'
import { hasFile, paramsToObject, toFormData, type Entry } from './params'

// The server compares this to the record's current value and answers 409 `stale` on a mismatch.
export const lockEntries = (lock?: FormLock): Entry[] => (lock ? [['lock[field]', lock.field], ['lock[value]', lock.value]] : [])

// The one place forms write. A form the server marked non-submittable never reaches the network.
// JSON unless a file is present, in which case Rails reads it as multipart.
export function saveRecord({ action: { method, path }, lock, submittable }: FormResponse, entries: Entry[]) {
  if (submittable === false) return Promise.reject(new Error("This form can't be saved here"))
  const all = [...entries, ...lockEntries(lock)]
  return apiFetch<WriteResult>(
    path,
    hasFile(all)
      ? { method: method.toUpperCase(), body: toFormData(all) }
      : { method: method.toUpperCase(), headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(paramsToObject(all)) },
  )
}
