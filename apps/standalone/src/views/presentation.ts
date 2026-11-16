import type { Action } from '@/api/generated/model'

// Short native forms read best as dialogs; HTML, iframes and host components get the whole page.
export const presentationOf = ({ view }: Action) => view?.presentation ?? (view?.mode === 'native' ? 'dialog' : 'page')

// Script needs the iframe, and only views the ladder already put there declare it; the rest fall back to the frame.
export const fallbackMode = ({ view }: Action) => (view?.mode === 'iframe' ? 'iframe' : 'frame')
