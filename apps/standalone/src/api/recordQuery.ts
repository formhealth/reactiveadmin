// Opening a record is a view the host audits, so it is always a fresh request: whatever the cache holds
// (a record seen moments ago) is shown while it loads, never in place of it.
export const openedRecordQuery = { refetchOnMount: 'always' } as const
