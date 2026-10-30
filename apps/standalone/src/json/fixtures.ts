// Synthetic data only; nothing here resembles a real record.
export const small = { publisher: 'Acme Media', active: true, price_cents: 3500, notes: null }

export const deep = {
  post: {
    id: 5000,
    indexing: {
      status: 'active',
      channels: { web: true, print: false, tiers: [{ code: 'T1', rate: 0.8 }, { code: 'T2', rate: 0.6 }] },
      history: [{ checked_at: '2026-10-14T09:30:00Z', result: { ok: true, detail: { source: 'crawler', latency_ms: 412 } } }],
    },
    labels: ['seo-1', 'seo-2', 'seo-3'],
  },
}

export const largeArray = {
  total: 240,
  revisions: Array.from({ length: 240 }, (_, i) => ({ seq: i + 1, words: 180 + (i % 7) * 0.4, source: i % 3 ? 'import' : 'manual' })),
}

export const withMasked = { publisher: 'Acme Media', reader_id: '[masked]', group: { number: 'G-1002', token_last4: '[masked]' } }

export const auditedChanges: Record<string, [unknown, unknown]> = {
  status: ['pending', 'published'],
  embargo_until: [null, '2026-11-01'],
  details: [{ author_state: 'MA', labels: ['seo-1'] }, { author_state: 'NH', labels: ['seo-1', 'seo-2'] }],
  reader_id: ['[masked]', '[masked]'],
}
