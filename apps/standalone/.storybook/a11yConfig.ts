// Shared by the story suite (vitest.setup.ts) and the end-to-end crawl (crawl/).
export const AXE_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa', 'best-practice']
export const BLOCKING_IMPACTS = ['serious', 'critical']
// Radix hides everything outside an open modal with aria-hidden while trapping focus, which axe can't see.
export const MODAL_SIBLINGS = [{ id: 'aria-hidden-focus', selector: '[aria-hidden="true"]:not([data-aria-hidden])' }]
// Stories render fragments, so whole-document rules would fire on every story; the crawl renders whole pages and keeps them.
export const FRAGMENT_RULES = ['region', 'page-has-heading-one', 'landmark-one-main']
