import { FrameBoundary } from '@/boundaries/FrameBoundary'
import { FrameView } from '@/frame/FrameView'
import { IframeView } from '@/frame/IframeView'
import type { NodeProps } from './Node'

export const FrameNode = ({ node }: NodeProps) => (
  <FrameBoundary src={node.src} title={node.title}>
    <FrameView src={node.src} html={node.html} title={node.title} />
  </FrameBoundary>
)

export const IframeNode = ({ node }: NodeProps) => (node.src ? <IframeView src={node.src} title={node.title} /> : null)
