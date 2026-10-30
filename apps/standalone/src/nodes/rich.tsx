import { useMemo } from 'react'
import { classicUrl } from '@/lib/classic'
import { purify } from '@/sanitize/purify'
import { useTrustedMediaHosts } from '@/hooks/useManifest'
import { useNodeContext } from './context'
import type { NodeProps } from './Node'

export function Html({ node }: NodeProps) {
  const { resource, id } = useNodeContext()
  const hosts = useTrustedMediaHosts()
  const clean = useMemo(() => purify(node.html ?? '', 'display', hosts), [node.html, hosts])
  return (
    <div className="rounded-md border bg-muted/40 p-3 text-sm">
      <div className="max-w-none space-y-2 [&_a]:underline [&_ol]:list-decimal [&_ol]:pl-5 [&_ul]:list-disc [&_ul]:pl-5" dangerouslySetInnerHTML={{ __html: clean }} />
      {resource && id && (
        <a
          href={classicUrl(resource, id)}
          className="mt-2 inline-block text-xs text-muted-foreground underline-offset-4 hover:underline"
        >
          Open in classic admin
        </a>
      )}
    </div>
  )
}
