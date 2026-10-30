import { useSyncExternalStore } from 'react'

export const useMediaQuery = (query: string) =>
  useSyncExternalStore(
    (notify) => {
      const list = matchMedia(query)
      list.addEventListener('change', notify)
      return () => list.removeEventListener('change', notify)
    },
    () => matchMedia(query).matches,
  )

export const useIsDesktop = () => useMediaQuery('(min-width: 1024px)')
export const useIsWide = () => useMediaQuery('(min-width: 640px)')
export const useIsXl = () => useMediaQuery('(min-width: 1280px)')
