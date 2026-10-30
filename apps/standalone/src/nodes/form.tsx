import { lazy, Suspense, useContext, useState } from 'react'
import { Skeleton } from '@/components/ui/skeleton'
import { safeFormAction } from '@/lib/safeUrl'
import { OwnFormContext } from './context'
import type { NodeProps } from './Node'

// Only the form itself needs react-hook-form and zod; a layout's own-form placeholder doesn't.
const InlineForm = lazy(() => import('./InlineForm').then((m) => ({ default: m.InlineForm })))

// A Formtastic form in a page's or show's content, rendered with the record form's own controls. It remounts
// after a send, so the next entry starts from the form as the page describes it. Without a payload it stands for
// the form of the template response whose layout this is.
export function FormNode({ node }: NodeProps) {
  const [sends, setSends] = useState(0)
  const own = useContext(OwnFormContext)
  if (!node.form) return own
  if (!safeFormAction(node.form)) return null
  // A filter form shows the query its page was loaded with, so it starts over when the page answers with other values.
  const loaded = node.form.action.method === 'get' ? JSON.stringify(node.form.form.sections) : ''
  return (
    <Suspense fallback={<Skeleton className="h-24 w-full max-w-xl" role="status" aria-label="Loading form" />}>
      <InlineForm key={`${sends}${loaded}`} response={node.form} onDone={() => setSends((n) => n + 1)} />
    </Suspense>
  )
}
