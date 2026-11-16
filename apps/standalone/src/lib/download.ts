import type { MouseEvent } from 'react'

// The demo's service worker only sees fetches made by the page, not the browser's own download requests, so the demo fetches the file and saves the blob.
export const fetchDownload = (href: string) => async (event: MouseEvent) => {
  event.preventDefault()
  const url = URL.createObjectURL(await (await fetch(href)).blob())
  Object.assign(document.createElement('a'), { href: url, download: new URL(href, location.href).pathname.split('/').at(-1) }).click()
  URL.revokeObjectURL(url)
}
