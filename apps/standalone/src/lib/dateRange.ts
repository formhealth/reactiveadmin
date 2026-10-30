import { format, parseISO } from 'date-fns'

const pretty = (value: string) => format(parseISO(value), 'MMM d, yyyy')

export const rangeLabel = (from?: string, to?: string) =>
  from && to ? (from === to ? pretty(from) : `${pretty(from)} – ${pretty(to)}`) : from ? `From ${pretty(from)}` : to ? `Until ${pretty(to)}` : 'Any'
