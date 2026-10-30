import type { ReactNode } from 'react'
import { Copy } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { shortId, UUID_IN_TEXT } from '@/lib/ids'
import { cn } from '@/lib/utils'

const copyId = async (value: string) => {
  try {
    await navigator.clipboard.writeText(value)
    toast('Copied ID')
  } catch {
    toast.error("Couldn't copy ID")
  }
}

const idClass = 'font-mono font-normal text-muted-foreground'

function CopyButton({ value, className }: { value: string; className?: string }) {
  return (
    <Button type="button" variant="ghost" size="icon-xs" aria-label="Copy ID" onClick={() => copyId(value)} className={cn('relative z-10', className)}>
      <Copy />
    </Button>
  )
}

/** Tooltip with the full id and a copy button, for any focusable trigger. */
export function IdTip({ value, children }: { value: string; children: ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>{children}</TooltipTrigger>
      <TooltipContent className="max-w-none gap-1 py-1 pr-1 pl-2 whitespace-nowrap">
        <span className="font-mono">{value}</span>
        <CopyButton value={value} className="text-background hover:bg-background/15 hover:text-background" />
      </TooltipContent>
    </Tooltip>
  )
}

export function IdValue({ value, full }: { value: string; full?: boolean }) {
  if (full)
    return (
      <span className="inline-flex items-center gap-1 font-mono">
        {value}
        <CopyButton value={value} className="text-muted-foreground" />
      </span>
    )
  return (
    <IdTip value={value}>
      <button
        type="button"
        aria-label={`Copy ID ${value}`}
        onClick={() => copyId(value)}
        className={cn(idClass, 'relative z-10 rounded-sm outline-none hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring')}
      >
        {shortId(value)}…
      </button>
    </IdTip>
  )
}

/** Text with any UUIDs replaced by their short form. */
export const TextWithIds = ({ text }: { text: string }) =>
  text.split(UUID_IN_TEXT).map((part, i) => (i % 2 ? <IdValue key={i} value={part} /> : part))
