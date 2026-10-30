import type { ComponentProps } from 'react'
import { Calendar } from '@/components/ui/calendar'

// Split out so react-day-picker loads when the popover first opens, not with the list page.
export function DateRangeCalendar(props: ComponentProps<typeof Calendar>) {
  return <Calendar {...props} />
}
