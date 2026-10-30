import { describe, expect, it } from 'vitest'
import { formatDay, formatMoment, parseDay, strftime } from './datetime'

const at = new Date('2026-10-04T13:05:09Z')
const ny = { timeZone: 'America/New_York' }

describe('strftime', () => {
  it('maps numeric, name and meridiem tokens through Intl', () => {
    expect(strftime(at, '%B %-d, %Y %-l:%M %p', ny)).toBe('October 4, 2026 9:05 AM')
    expect(strftime(at, '%a %b %e %H:%M:%S %Y', ny)).toBe('Sun Oct  4 09:05:09 2026')
    expect(strftime(at, '%m/%d/%y %I:%M%P', ny)).toBe('10/04/26 09:05am')
  })

  it('reads fields in the requested time zone', () => {
    expect(strftime(at, '%H:%M %Z', { timeZone: 'UTC' })).toBe('13:05 UTC')
    expect(strftime(at, '%H:%M', { timeZone: 'Asia/Tokyo' })).toBe('22:05')
    expect(strftime(at, '%z', ny)).toBe('-0400')
    expect(strftime(at, '%z', { timeZone: 'UTC' })).toBe('+0000')
  })

  it('expands composites, flags and escapes', () => {
    expect(strftime(at, '%F %T', ny)).toBe('2026-10-04 09:05:09')
    expect(strftime(at, '%^b %-m%%', ny)).toBe('OCT 10%')
    expect(strftime(at, '%Q', ny)).toBe('%Q')
  })

  it('localizes names', () => {
    expect(strftime(at, '%A %B', { ...ny, locale: 'es' })).toBe('domingo octubre')
  })

  it('wraps midnight to 12 on a 12-hour clock', () => {
    expect(strftime(new Date('2026-10-04T04:00:00Z'), '%l:%M %p %H', ny)).toBe('12:00 AM 00')
  })
})

describe('display helpers', () => {
  it('formats calendar days without shifting them', () => {
    expect(formatDay(parseDay('2026-10-04')!)).toBe('Oct 4, 2026')
    expect(formatDay(parseDay('2026-10-04')!, { dateFormat: '%B %d, %Y' })).toBe('October 04, 2026')
    expect(parseDay('nope')).toBeUndefined()
  })

  it('omits the year for moments in the current year unless a format is set', () => {
    const now = new Date('2026-12-01T00:00:00Z')
    expect(formatMoment(at, ny, now)).toBe('Oct 4, 9:05 AM')
    expect(formatMoment(new Date('2025-10-04T13:05:00Z'), ny, now)).toBe('Oct 4, 2025 9:05 AM')
    expect(formatMoment(at, { ...ny, dateTimeFormat: '%Y-%m-%d %H:%M' }, now)).toBe('2026-10-04 09:05')
  })
})
