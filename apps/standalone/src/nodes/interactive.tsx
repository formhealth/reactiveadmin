import { ActionButton } from '@/components/ActionBar'
import { useRecordAction } from '@/hooks/useRecordAction'
import { safeAction } from '@/lib/safeUrl'
import { useNodeContext } from './context'
import type { NodeProps } from './Node'

// A non-GET button or link in content (rails-ujs `data-method`, `button_to`): never a plain link, so it runs through
// the same confirm, toast and refetch path as the header actions.
export function ActionNode({ node }: NodeProps) {
  const ctx = useNodeContext()
  const { request, dialogs } = useRecordAction(ctx)
  if (!node.action || !safeAction(node.action)) return null
  return (
    <div className="flex self-start">
      <ActionButton action={node.action} run={request} size="sm" />
      {dialogs}
    </div>
  )
}
