import { ExternalLink } from 'lucide-react'
import { withClassic } from '@/lib/classic'

// The classic admin is the host's own page, so it opens beside the app rather than replacing it. Takes the props
// of the `asChild` parents (Button, menu items) that render it.
export function ClassicLink({ children, href, ...props }: React.ComponentProps<'a'> & { href: string }) {
  return (
    <a {...props} href={withClassic(href)} target="_blank" rel="noopener noreferrer">
      {children}
      <ExternalLink aria-hidden />
      <span className="sr-only">(opens in the classic admin, in a new tab)</span>
    </a>
  )
}
