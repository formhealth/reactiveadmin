import { createElement } from 'react'
import type { LucideIcon } from 'lucide-react'
import { iconFor } from '@/lib/icons'
import { cn } from '@/lib/utils'

type MenuIconProps = { name?: string | null; fallback?: LucideIcon; className?: string }

// A menu item's icon by name; the fallback (or nothing) when the name isn't in the curated set.
export function MenuIcon({ name, fallback, className }: MenuIconProps) {
  const icon = iconFor(name) ?? fallback
  return icon ? createElement(icon, { 'aria-hidden': true, className: cn('size-4 shrink-0', className) }) : null
}
