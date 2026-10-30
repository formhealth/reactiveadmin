import type { CSSProperties } from 'react'
import type { Node as NodeData } from '@/api/generated/model'
import { cn } from '@/lib/utils'

type Vars = CSSProperties & Record<string, string>

// Tone is meaning, not color: the design system picks the shade.
export const TONE = { muted: 'text-muted-foreground', success: 'text-success', danger: 'text-danger', warning: 'text-warning' } as const
export const MAX_WIDTH = { sm: 'max-w-sm', md: 'max-w-md', lg: 'max-w-lg', xl: 'max-w-xl', '2xl': 'max-w-2xl' } as const

// Margins travel as CSS variables so Tailwind sees every class name.
const MARGIN = {
  top: ['mt-(--mt)', '--mt'],
  right: ['mr-(--mr)', '--mr'],
  bottom: ['mb-(--mb)', '--mb'],
  left: ['ml-(--ml)', '--ml'],
} as const

export function spacingOf(spacing: NodeData['spacing']): { style: Vars; className: string } {
  const style: Vars = {}
  const classes: string[] = []
  for (const [side, [className, variable]] of Object.entries(MARGIN)) {
    const steps = spacing?.[side as keyof typeof MARGIN]
    if (!steps) continue
    style[variable] = `calc(var(--spacing) * ${steps})`
    classes.push(className)
  }
  return { style, className: cn(classes) }
}

// What a box's marks and tone do to its content, by inheritance.
export const emphasisOf = (node: NodeData) =>
  cn(node.marks?.includes('strong') && 'font-semibold', node.marks?.includes('em') && 'italic', node.tone && TONE[node.tone], node.nowrap && 'whitespace-nowrap')
