export type Formats = { timeZone?: string; locale?: string; dateFormat?: string | null; dateTimeFormat?: string | null }

const formatters = new Map<string, Intl.DateTimeFormat>()

const intl = (locale: string | undefined, options: Intl.DateTimeFormatOptions) => {
  const key = JSON.stringify([locale, options])
  if (!formatters.has(key)) formatters.set(key, new Intl.DateTimeFormat(locale, options))
  return formatters.get(key)!
}

type Fields = Record<'year' | 'month' | 'day' | 'hour' | 'minute' | 'second', number>

// Numbers come from one en-US pass so padding is ours; Intl's 2-digit minute alone yields "5".
const fieldsOf = (date: Date, timeZone?: string) =>
  Object.fromEntries(
    intl('en-US', { timeZone, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' })
      .formatToParts(date)
      .filter((p) => p.type !== 'literal')
      .map((p) => [p.type, Number(p.value)]),
  ) as Fields

const COMPOSITES: Record<string, string> = { F: '%Y-%m-%d', T: '%H:%M:%S', D: '%m/%d/%y', R: '%H:%M', r: '%I:%M:%S %p' }

const offsetOf = (date: Date, locale: string | undefined, timeZone?: string) => {
  const raw = intl(locale, { timeZone, timeZoneName: 'longOffset' }).formatToParts(date).find((p) => p.type === 'timeZoneName')?.value ?? 'GMT'
  const [, sign = '+', h = '00', m = '00'] = /([+-])(\d{2}):?(\d{2})?/.exec(raw) ?? []
  return `${sign}${h}${m}`
}

// Renders a Ruby strftime pattern (the form AA's localize_format yields) through Intl, so month and weekday
// names follow the locale and every field is read in the site's time zone.
export function strftime(date: Date, pattern: string, { timeZone, locale }: { timeZone?: string; locale?: string } = {}) {
  const f = fieldsOf(date, timeZone)
  const named = (options: Intl.DateTimeFormatOptions, type: Intl.DateTimeFormatPartTypes) =>
    intl(locale, { timeZone, ...options }).formatToParts(date).find((p) => p.type === type)?.value ?? ''
  const hour12 = f.hour % 12 || 12

  return pattern
    .replace(/%([-_0^]?)([FTDRr])/g, (_, __, c) => COMPOSITES[c])
    .replace(/%([-_0^]?)([a-zA-Z%])/g, (token, flag: string, c: string) => {
      const num = (n: number, fill = '0') => (flag === '-' ? String(n) : String(n).padStart(2, flag === '_' ? ' ' : flag === '0' ? '0' : fill))
      const text = (value: string) => (flag === '^' ? value.toUpperCase() : value)
      switch (c) {
        case 'Y': return String(f.year)
        case 'y': return num(f.year % 100)
        case 'm': return num(f.month)
        case 'd': return num(f.day)
        case 'e': return num(f.day, ' ')
        case 'H': return num(f.hour)
        case 'k': return num(f.hour, ' ')
        case 'I': return num(hour12)
        case 'l': return num(hour12, ' ')
        case 'M': return num(f.minute)
        case 'S': return num(f.second)
        case 'B': return text(named({ month: 'long' }, 'month'))
        case 'b':
        case 'h': return text(named({ month: 'short' }, 'month'))
        case 'A': return text(named({ weekday: 'long' }, 'weekday'))
        case 'a': return text(named({ weekday: 'short' }, 'weekday'))
        case 'p': return text(named({ hour: 'numeric', hour12: true }, 'dayPeriod'))
        case 'P': return named({ hour: 'numeric', hour12: true }, 'dayPeriod').toLowerCase()
        case 'Z': return text(named({ timeZoneName: 'short' }, 'timeZoneName'))
        case 'z': return offsetOf(date, locale, timeZone)
        case 's': return String(Math.floor(date.getTime() / 1000))
        case '%': return '%'
        default: return token
      }
    })
}

const DAY = /^(\d{4})-(\d{2})-(\d{2})/

// A calendar day has no zone: it is anchored at UTC midnight and always formatted in UTC.
export function parseDay(value: unknown) {
  const [, y, m, d] = DAY.exec(String(value)) ?? []
  return y ? new Date(Date.UTC(+y, +m - 1, +d)) : undefined
}

export function parseMoment(value: unknown) {
  const date = new Date(String(value))
  return Number.isNaN(date.getTime()) ? undefined : date
}

export const formatDay = (date: Date, { locale, dateFormat }: Formats = {}) => strftime(date, dateFormat ?? '%b %-d, %Y', { timeZone: 'UTC', locale })

export function formatMoment(date: Date, { timeZone, locale, dateTimeFormat }: Formats = {}, now = new Date()) {
  const thisYear = fieldsOf(date, timeZone).year === fieldsOf(now, timeZone).year
  return strftime(date, dateTimeFormat ?? (thisYear ? '%b %-d, %-l:%M %p' : '%b %-d, %Y %-l:%M %p'), { timeZone, locale })
}
