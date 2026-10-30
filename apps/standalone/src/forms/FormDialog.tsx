import type { FormResponse } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { RecordForm, SubmitButton } from './RecordForm'
import type { Entry } from './params'
import { useRecordForm } from './useRecordForm'

type FormDialogProps<T> = {
  response: FormResponse
  submitLabel: string
  send: (entries: Entry[]) => Promise<T>
  onDone: (result: T) => void
  onClose: () => void
  description?: string
  classicHref?: string
}

function DialogForm<T>({ response, submitLabel, send, onDone, onClose, description, classicHref }: FormDialogProps<T>) {
  const form = useRecordForm(response, { classicHref })
  return (
    <DialogContent className="max-h-[90dvh] gap-4 overflow-y-auto sm:max-w-lg">
      <DialogHeader>
        <DialogTitle>{response.title}</DialogTitle>
        <DialogDescription className={description ? undefined : 'sr-only'}>{description ?? response.title}</DialogDescription>
      </DialogHeader>
      <RecordForm form={form} plain onSubmit={form.submit(send, onDone)}>
        <DialogFooter className="mt-1">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <SubmitButton form={form} label={submitLabel} pendingLabel="Working…" />
        </DialogFooter>
      </RecordForm>
    </DialogContent>
  )
}

export function FormDialog<T>(props: FormDialogProps<T> & { open: boolean }) {
  const { open, ...rest } = props
  return (
    <Dialog open={open} onOpenChange={(next) => !next && props.onClose()}>
      {open && <DialogForm {...rest} />}
    </Dialog>
  )
}
