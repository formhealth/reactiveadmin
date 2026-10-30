import type { Column, Row } from '@/api/generated/model'

export type Tone = NonNullable<Row['tone']>

export const rowTone: Record<Tone, string> = {
  success: 'bg-success-soft',
  warning: 'bg-warning-soft',
  danger: 'bg-danger-soft',
  info: 'bg-info-soft',
}

const TEXT = { success: 'text-success', warning: 'text-warning', danger: 'text-danger', info: 'text-info', muted: 'text-muted-foreground' }

// `column class:` is free-form CSS from the classic admin. Only words that name a tone are honoured; the rest is dropped.
export function columnTextClass(className?: string | null) {
  const words = (className ?? '').toLowerCase().split(/[\s_-]+/)
  const tone = words.includes('error') ? 'danger' : (Object.keys(TEXT) as (keyof typeof TEXT)[]).find((key) => words.includes(key))
  return tone && TEXT[tone]
}

export const alignClass = (align?: Column['align']) => (align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : undefined)
