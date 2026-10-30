import { CircleAlert } from 'lucide-react'
import type { FormField } from '@/api/generated/model'
import { ClassicLink } from '@/components/ApiDenied'
import { Label } from '@/components/ui/label'
import { cn } from '@/lib/utils'
import { useDense } from './dense'
import type { FieldState } from './useField'

export const Hint = ({ id, children }: { id: string; children: React.ReactNode }) => (
  <p id={`${id}-hint`} className="text-xs text-muted-foreground">
    {children}
  </p>
)

export const FieldError = ({ id, children }: { id: string; children: React.ReactNode }) => (
  <p id={`${id}-error`} className="flex items-start gap-1.5 text-xs font-medium text-danger">
    <CircleAlert className="mt-0.5 size-3.5 shrink-0" aria-hidden />
    {children}
  </p>
)

type ShellProps = {
  field: FormField
  state: FieldState
  // Radio and checkbox groups label a role="group" instead of a single input.
  group?: boolean
  action?: React.ReactNode
  className?: string
  children: React.ReactNode
}

export const RequiredMark = () => (
  <>
    <span aria-hidden className="text-danger">
      *
    </span>
    <span className="sr-only">(required)</span>
  </>
)

export function FieldShell({ field, state, group, action, className, children }: ShellProps) {
  const { id, error } = state
  const dense = useDense()
  if (dense)
    return (
      <div className="flex w-full flex-col gap-1">
        <Label htmlFor={id} className="sr-only">
          {dense.label}
        </Label>
        {children}
        {error && <FieldError id={id}>{error}</FieldError>}
      </div>
    )
  return (
    <div className={cn('flex w-full max-w-xl flex-col gap-1.5', className)}>
      <div className="flex items-end justify-between gap-2">
        {group ? (
          <span id={`${id}-label`} className="flex items-center gap-1 text-sm font-medium">
            {field.label}
            {field.required && <RequiredMark />}
          </span>
        ) : (
          <Label htmlFor={id} className="gap-1">
            {field.label}
            {field.required && <RequiredMark />}
          </Label>
        )}
        {action}
      </div>
      {group ? (
        <div role="group" aria-labelledby={`${id}-label`} aria-describedby={state.aria['aria-describedby']} className="flex flex-col gap-2">
          {children}
        </div>
      ) : (
        children
      )}
      {field.api_denied && field.classic_url && (
        <p className="text-xs text-muted-foreground">
          Only the classic admin can change this.{' '}
          <ClassicLink href={field.classic_url} className="inline-flex items-center gap-1 underline underline-offset-2 hover:text-foreground [&_svg]:size-3">
            Open in classic admin
          </ClassicLink>
        </p>
      )}
      {field.hint && <Hint id={id}>{field.hint}</Hint>}
      {error && <FieldError id={id}>{error}</FieldError>}
    </div>
  )
}
