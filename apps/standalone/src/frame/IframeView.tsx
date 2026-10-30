import { useEffect, useRef, useState } from 'react'
import { ExternalLink } from 'lucide-react'
import { useNavigate } from 'react-router'
import { toast } from 'sonner'
import { useMapClassic } from '@/hooks/useManifest'
import { safeEmbedSrc } from '@/lib/safeUrl'
import { cn } from '@/lib/utils'
import { navigation, parseBridgeMessage, trustedOrigin } from './bridge'
import { classicLink } from './request'

const MIN_HEIGHT = 160

type IframeViewProps = { src: string; title?: string | null; bare?: boolean; onLeave?: () => void }

// A same-origin classic page rendered with `?embed=1` (no chrome). It talks back with postMessage: its body height
// (`reactiveadmin:resize`), flashes, and links to other admin pages, which become in-app routes where the client has a
// screen and otherwise stay in the iframe.
export function IframeView({ src, ...props }: IframeViewProps) {
  const safe = safeEmbedSrc(src)
  return safe ? <EmbeddedPage src={safe} {...props} /> : null
}

// Same-origin scripts and forms run (the classic page needs its own JS, session cookie and bridge), and so do modals
// (`data-confirm`), downloads (CSV links) and popups that leave the sandbox (`target=_blank`). Nothing else is granted,
// notably `allow-top-navigation`: the framed page can't navigate the app away. Same-origin scripts can lift the sandbox
// themselves, so it is no isolation: `safeEmbedSrc` (admin paths only) is the boundary. Popups escape because host
// pages open Sidekiq and other tools with `target=_blank`.
const SANDBOX = 'allow-same-origin allow-scripts allow-forms allow-modals allow-downloads allow-popups allow-popups-to-escape-sandbox'

function EmbeddedPage({ src, title, bare, onLeave }: IframeViewProps) {
  const frame = useRef<HTMLIFrameElement>(null)
  const navigate = useNavigate()
  const mapUrl = useMapClassic()
  // Where the iframe was sent from inside; a new `src` prop starts over.
  const [visited, setVisited] = useState({ from: src, url: src })
  const current = visited.from === src ? visited.url : src
  const [height, setHeight] = useState(480)

  useEffect(() => {
    const onMessage = ({ origin, source, data }: MessageEvent) => {
      if (!trustedOrigin(origin) || source !== frame.current?.contentWindow) return
      const event = parseBridgeMessage(data)
      if (event?.kind === 'resize') setHeight(Math.max(MIN_HEIGHT, event.height))
      if (event?.kind === 'flash') event.flashes.forEach(({ level, message }) => (level === 'error' ? toast.error : toast.success)(message))
      if (event?.kind === 'navigate') {
        const next = navigation(event, mapUrl)
        if (next && 'to' in next) {
          onLeave?.()
          navigate(next.to)
        } else if (next && safeEmbedSrc(next.stay)) setVisited({ from: src, url: next.stay })
      }
    }
    window.addEventListener('message', onMessage)
    return () => window.removeEventListener('message', onMessage)
  }, [mapUrl, navigate, onLeave, src])

  return (
    <section aria-label={title ?? 'Embedded page'} className={cn('flex min-w-0 flex-col overflow-hidden', !bare && 'rounded-lg border bg-card')}>
      <iframe ref={frame} src={current} title={title ?? 'Embedded page'} loading="lazy" referrerPolicy="same-origin" sandbox={SANDBOX} style={{ height }} className="block w-full border-0" />
      <footer className={cn('flex items-center justify-end text-xs text-muted-foreground', bare ? 'pt-2' : 'border-t px-4 py-2')}>
        <a href={classicLink(current)} className="inline-flex items-center gap-1 underline-offset-4 hover:underline">
          Open in classic admin
          <ExternalLink className="size-3" aria-hidden />
        </a>
      </footer>
    </section>
  )
}
