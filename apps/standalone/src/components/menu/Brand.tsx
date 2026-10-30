import { NavLink } from 'react-router'
import { Skeleton } from '@/components/ui/skeleton'
import { useSite } from '@/hooks/useManifest'
import { sameOrigin } from '@/lib/classic'

const className = 'flex min-w-0 items-center gap-2 text-base font-semibold'

// The site's own title (and logo); it links home in the app unless AA points it at an outside site.
export function Brand({ onNavigate }: { onNavigate?: () => void }) {
  const site = useSite()
  if (!site) return <Skeleton className="h-5 w-28" aria-hidden />

  const content = (
    <>
      {site.title_image && <img src={site.title_image} alt="" className="h-6 w-auto shrink-0" />}
      <span className="truncate">{site.title}</span>
    </>
  )
  const outside = site.title_link && /^https?:/i.test(site.title_link) && !sameOrigin(site.title_link)
  return outside ? (
    <a href={site.title_link!} className={className}>
      {content}
    </a>
  ) : (
    <NavLink to="/" onClick={onNavigate} className={className}>
      {content}
    </NavLink>
  )
}
