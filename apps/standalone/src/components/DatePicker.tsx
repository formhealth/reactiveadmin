import { useState, type ComponentProps } from 'react'
import { format, isValid, parseISO } from 'date-fns'
import { CalendarIcon } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Calendar } from '@/components/ui/calendar'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { useFormats } from '@/hooks/useManifest'
import { formatDay, parseDay } from '@/lib/datetime'
import { cn } from '@/lib/utils'

const DAY = 'yyyy-MM-dd'

type DatePickerProps = Omit<ComponentProps<typeof Button>, 'onChange' | 'value'> & {
  value: string
  onChange: (day: string) => void
  onCommit?: () => void
  clearable?: boolean
  placeholder?: string
  min?: string
  max?: string
}

// `value` and `onChange` carry a plain `yyyy-MM-dd` day, the shape both forms and classic inputs submit.
export function DatePicker({ value, onChange, onCommit, clearable, placeholder = 'Select date', min, max, className, 'aria-required': _required, ...button }: DatePickerProps) {
  const [open, setOpen] = useState(false)
  const formats = useFormats()
  const day = parseDay(value)
  const selected = value ? parseISO(value) : undefined
  const [from, to] = [min, max].map((bound) => (bound ? parseISO(bound) : undefined)).map((d) => (d && isValid(d) ? d : undefined))
  const disabled = [from && { before: from }, to && { after: to }].filter((matcher) => !!matcher)
  const commit = (next: string) => {
    onChange(next)
    onCommit?.()
    setOpen(false)
  }
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button type="button" variant="outline" {...button} className={cn('w-full justify-start bg-transparent font-normal aria-invalid:border-destructive sm:w-48', className)}>
          <CalendarIcon className="opacity-60" />
          {day ? formatDay(day, formats) : <span className="text-muted-foreground">{placeholder}</span>}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" aria-label="Choose a date" className="w-auto gap-0 p-0">
        <Calendar mode="single" selected={selected && isValid(selected) ? selected : undefined} defaultMonth={selected} startMonth={from} endMonth={to} disabled={disabled} onSelect={(d) => d && commit(format(d, DAY))} />
        {clearable && day && (
          <Button type="button" variant="ghost" size="sm" className="m-1 mt-0 justify-start text-muted-foreground" onClick={() => commit('')}>
            Clear
          </Button>
        )}
      </PopoverContent>
    </Popover>
  )
}
