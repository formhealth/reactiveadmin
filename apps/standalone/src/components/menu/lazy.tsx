import { lazy, Suspense, useState, type ComponentProps } from 'react'

// Both open on demand, so cmdk and the sheet stay out of the shell bundle. Once opened they stay mounted
// so Radix can play the close animation.
const Palette = lazy(() => import('./CommandPalette').then((m) => ({ default: m.CommandPalette })))
const Mobile = lazy(() => import('./MobileMenu').then((m) => ({ default: m.MobileMenu })))

function useOpenedOnce(open: boolean) {
  const [opened, setOpened] = useState(open)
  if (open && !opened) setOpened(true)
  return opened
}

export function LazyCommandPalette(props: ComponentProps<typeof Palette>) {
  const opened = useOpenedOnce(props.open)
  return opened && <Suspense><Palette {...props} /></Suspense>
}

export function LazyMobileMenu(props: ComponentProps<typeof Mobile>) {
  const opened = useOpenedOnce(props.open)
  return opened && <Suspense><Mobile {...props} /></Suspense>
}
