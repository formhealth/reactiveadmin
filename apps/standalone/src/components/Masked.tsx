import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'

// The server withheld the value; nothing real is ever in the payload.
export function Masked() {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span tabIndex={0} className="cursor-help rounded-sm font-mono tracking-widest text-muted-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <span aria-hidden>••••••</span>
          <span className="sr-only">Hidden for security</span>
        </span>
      </TooltipTrigger>
      <TooltipContent>Hidden for security</TooltipContent>
    </Tooltip>
  )
}
