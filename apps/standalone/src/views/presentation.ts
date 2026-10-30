import type { Action } from '@/api/generated/model'

// Short native forms read best as dialogs; HTML, iframes and host components get the whole page.
export const presentationOf = ({ view }: Action) => view?.presentation ?? (view?.mode === 'native' ? 'dialog' : 'page')
