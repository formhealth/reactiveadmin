import { useState } from 'react'
import { Download, ExternalLink, FileText, Maximize2, ZoomIn, ZoomOut } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { useTrustedMediaHosts } from '@/hooks/useManifest'
import { safeMediaSrc } from '@/lib/safeMedia'
import type { NodeProps } from './Node'

// Documents and images load straight from their host into the browser, never through this app's server. The no-referrer
// policy keeps the admin URL (record ids) from reaching the CDN.
const NO_REFERRER = 'no-referrer'
const ZOOMS = [1, 1.5, 2, 3]

export function ImageNode({ node }: NodeProps) {
  const src = safeMediaSrc(node.src, useTrustedMediaHosts())
  const [failed, setFailed] = useState(false)
  if (!src) return null
  const alt = node.alt ?? ''
  const label = alt || 'Image'

  if (failed) {
    return (
      <p className="text-sm text-muted-foreground">
        {label} couldn&apos;t be loaded.{' '}
        <a href={src} target="_blank" rel="noopener noreferrer" referrerPolicy={NO_REFERRER} className="underline underline-offset-4">
          Open it in a new tab
        </a>
      </p>
    )
  }

  return (
    <Dialog>
      <DialogTrigger asChild>
        <button type="button" aria-label={`View larger: ${label}`} className="block max-w-full cursor-zoom-in self-start rounded-md focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none">
          <img
            src={src}
            alt={alt}
            width={node.width_px}
            height={node.height_px}
            loading="lazy"
            decoding="async"
            referrerPolicy={NO_REFERRER}
            onError={() => setFailed(true)}
            className="h-auto max-h-96 max-w-full rounded-md border object-contain"
          />
        </button>
      </DialogTrigger>
      <DialogContent className="gap-3 sm:max-w-[min(64rem,calc(100%-2rem))]">
        <Lightbox src={src} alt={alt} label={label} />
      </DialogContent>
    </Dialog>
  )
}

// `+`, `-` and `0` zoom, fit and reset from the keyboard; the scroll area takes focus so arrow keys pan a zoomed image.
function Lightbox({ src, alt, label }: { src: string; alt: string; label: string }) {
  const [zoom, setZoom] = useState<number | null>(null)
  const [naturalWidth, setNaturalWidth] = useState<number>()
  const step = (direction: 1 | -1) =>
    setZoom((current) => {
      const next = (current == null ? -1 : ZOOMS.indexOf(current)) + direction
      return next < 0 ? null : ZOOMS[Math.min(next, ZOOMS.length - 1)]
    })
  const onKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === '+' || event.key === '=') step(1)
    else if (event.key === '-') step(-1)
    else if (event.key === '0') setZoom(null)
    else return
    event.preventDefault()
  }

  return (
    <div className="grid gap-3" onKeyDown={onKeyDown}>
      <DialogHeader className="flex-row items-center gap-2 pr-8">
        <DialogTitle className="min-w-0 flex-1 truncate">{label}</DialogTitle>
        <DialogDescription className="sr-only">Use plus and minus to zoom, zero to fit the window.</DialogDescription>
        <Button variant="outline" size="icon-sm" aria-label="Zoom out" disabled={zoom == null} onClick={() => step(-1)}>
          <ZoomOut />
        </Button>
        <span aria-live="polite" className="w-12 text-center text-xs text-muted-foreground tabular-nums">
          {zoom == null ? 'Fit' : `${zoom * 100}%`}
        </span>
        <Button variant="outline" size="icon-sm" aria-label="Zoom in" disabled={zoom === ZOOMS.at(-1)} onClick={() => step(1)}>
          <ZoomIn />
        </Button>
        <Button variant="outline" size="icon-sm" aria-label="Fit to window" disabled={zoom == null} onClick={() => setZoom(null)}>
          <Maximize2 />
        </Button>
        <Button variant="outline" size="icon-sm" aria-label="Open in new tab" asChild>
          <a href={src} target="_blank" rel="noopener noreferrer" referrerPolicy={NO_REFERRER}>
            <ExternalLink />
          </a>
        </Button>
      </DialogHeader>
      <div tabIndex={0} role="group" aria-label={`${label}, zoomable`} className="max-h-[75vh] overflow-auto rounded-md bg-muted/40 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none">
        <img
          src={src}
          alt={alt}
          referrerPolicy={NO_REFERRER}
          onLoad={(event) => setNaturalWidth(event.currentTarget.naturalWidth)}
          style={zoom != null && naturalWidth ? { width: naturalWidth * zoom, maxWidth: 'none' } : undefined}
          className={zoom == null || !naturalWidth ? 'mx-auto max-h-[75vh] max-w-full object-contain' : 'mx-auto block h-auto'}
        />
      </div>
    </div>
  )
}

export function DocumentNode({ node }: NodeProps) {
  const src = safeMediaSrc(node.src, useTrustedMediaHosts())
  if (!src || node.mime !== 'application/pdf') return null
  const title = node.title || 'PDF document'

  return (
    <section aria-label={title} className="flex min-w-0 flex-col overflow-hidden rounded-lg border bg-card">
      <header className="flex items-center gap-2 border-b px-3 py-1.5">
        <FileText className="size-4 shrink-0 text-muted-foreground" aria-hidden />
        <h4 className="min-w-0 flex-1 truncate text-sm font-medium">{title}</h4>
        <Button variant="ghost" size="sm" asChild>
          <a href={src} target="_blank" rel="noopener noreferrer" referrerPolicy={NO_REFERRER} aria-label="Open in new tab">
            <ExternalLink /> <span className="hidden sm:inline">Open in new tab</span>
          </a>
        </Button>
        {/* Browsers ignore `download` across origins, so a CDN link opens in a tab and the viewer's own save button applies. */}
        <Button variant="ghost" size="sm" asChild>
          <a href={src} download target="_blank" rel="noopener noreferrer" referrerPolicy={NO_REFERRER} aria-label="Download">
            <Download /> <span className="hidden sm:inline">Download</span>
          </a>
        </Button>
      </header>
      <iframe src={src} title={title} loading="lazy" referrerPolicy={NO_REFERRER} className="block h-[70vh] max-h-[56rem] min-h-96 w-full border-0 bg-muted/40" />
      <footer className="border-t px-3 py-1.5 text-xs text-muted-foreground">
        Preview blank or blocked by your browser? <a href={src} target="_blank" rel="noopener noreferrer" referrerPolicy={NO_REFERRER} className="underline underline-offset-4">Open the document</a> instead.
      </footer>
    </section>
  )
}
