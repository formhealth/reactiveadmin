import type { ReactNode } from 'react'
import { IframeView } from '@/frame/IframeView'
import { classicLink } from '@/frame/request'
import { ErrorBoundary } from './ErrorBoundary'
import { Chip } from './fallbacks'
import { NodeChip } from './NodeBoundary'
import { embedded } from './urls'

// A frame that fails to render degrades to the same page in an iframe, then to a link; the classic page always works.
export function FrameBoundary({ src, title, children }: { src?: string | null; title?: string | null; children: ReactNode }) {
  return (
    <ErrorBoundary where="frame" fallback={() => (src ? <IframeBoundary src={src} title={title} /> : <NodeChip />)}>
      {children}
    </ErrorBoundary>
  )
}

function IframeBoundary({ src, title }: { src: string; title?: string | null }) {
  return (
    <ErrorBoundary where="iframe" fallback={() => <Chip href={classicLink(src)} />}>
      <IframeView src={embedded(src)} title={title} />
    </ErrorBoundary>
  )
}
