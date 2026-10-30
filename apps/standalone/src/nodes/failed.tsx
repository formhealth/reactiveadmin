import { useState } from 'react'
import { Check, Copy, TriangleAlert } from 'lucide-react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import type { NodeProps } from './Node'

// A value the server tried to render and couldn't. Distinct from `empty`, which means there is nothing to show.
export function ErrorNode({ node }: NodeProps) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span tabIndex={0} className="inline-flex cursor-help items-center gap-1 rounded-sm text-muted-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <TriangleAlert className="size-3.5 shrink-0 text-warning" aria-hidden />
          <span>{node.label ?? "Couldn't display"}</span>
          <span className="sr-only">. This value couldn't be displayed</span>
        </span>
      </TooltipTrigger>
      <TooltipContent>This value couldn't be displayed</TooltipContent>
    </Tooltip>
  )
}

// `language` is a hint only; nothing is highlighted, so it is shown as a label and never interpreted.
export function CodeNode({ node }: NodeProps) {
  const [copied, setCopied] = useState(false)
  const { text = '', language } = node as NodeProps['node'] & { language?: string }

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      toast.error("Couldn't copy")
    }
  }

  return (
    <div className="group/code relative max-w-full rounded-md border bg-muted">
      {language && <span className="absolute top-1.5 left-2 font-mono text-[0.65rem] tracking-wide text-muted-foreground uppercase select-none">{language}</span>}
      <pre tabIndex={0} className={`max-h-96 overflow-auto p-3 pr-11 font-mono text-xs/relaxed break-words whitespace-pre-wrap outline-none focus-visible:ring-2 focus-visible:ring-ring ${language ? 'pt-6' : ''}`}>
        <code>{text}</code>
      </pre>
      <Button type="button" variant="ghost" size="icon-xs" aria-label={copied ? 'Copied' : 'Copy to clipboard'} onClick={copy} className="absolute top-1.5 right-1.5 text-muted-foreground">
        {copied ? <Check /> : <Copy />}
      </Button>
    </div>
  )
}
