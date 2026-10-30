import { Button } from '@/components/ui/button'

type Props<T extends string> = { label: string; value: T; options: { value: T; label: string }[]; onChange: (value: T) => void; disabled?: boolean }

export function Segmented<T extends string>({ label, value, options, onChange, disabled }: Props<T>) {
  return (
    <div role="group" aria-label={label} className="inline-flex gap-0.5 rounded-lg bg-muted p-0.5">
      {options.map((option) => (
        <Button
          key={option.value}
          type="button"
          size="xs"
          variant={option.value === value ? 'secondary' : 'ghost'}
          aria-pressed={option.value === value}
          disabled={disabled}
          className={option.value === value ? 'bg-card shadow-xs' : 'text-muted-foreground'}
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </Button>
      ))}
    </div>
  )
}
