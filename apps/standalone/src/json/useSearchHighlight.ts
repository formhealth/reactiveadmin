import { useEffect, type RefObject } from 'react'

const TEXT = '.jer-key-text, .jer-input-component'

// The viewer filters to matching nodes but doesn't mark the match, so paint it with the CSS Custom Highlight
// API: no DOM changes to fight the viewer's renders. Browsers without it still get the filtering.
export function useSearchHighlight(root: RefObject<HTMLElement | null>, query: string, name: string) {
  useEffect(() => {
    const el = root.current
    if (!el || !query || typeof CSS === 'undefined' || !('highlights' in CSS)) return
    const term = query.toLowerCase()

    const paint = () => {
      const ranges: Range[] = []
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT)
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!node.parentElement?.closest(TEXT)) continue
        const text = node.textContent?.toLowerCase() ?? ''
        for (let at = text.indexOf(term); at >= 0; at = text.indexOf(term, at + term.length)) {
          const range = new Range()
          range.setStart(node, at)
          range.setEnd(node, at + term.length)
          ranges.push(range)
        }
      }
      CSS.highlights.set(name, new Highlight(...ranges))
    }

    let frame = 0
    const observer = new MutationObserver(() => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(paint)
    })
    observer.observe(el, { subtree: true, childList: true, characterData: true })
    paint()
    return () => {
      observer.disconnect()
      cancelAnimationFrame(frame)
      CSS.highlights.delete(name)
    }
  }, [root, query, name])
}
