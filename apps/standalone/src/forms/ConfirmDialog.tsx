import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'

// The question the classic submit button asked (`data-confirm`), answered before anything is sent.
export function ConfirmDialog({ title, question, answer }: { title: string; question?: string; answer: (ok: boolean) => void }) {
  return (
    <AlertDialog open={!!question} onOpenChange={(open) => !open && answer(false)}>
      <AlertDialogContent>
        <AlertDialogTitle>{title}</AlertDialogTitle>
        <AlertDialogDescription>{question}</AlertDialogDescription>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction onClick={() => answer(true)}>{title}</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
