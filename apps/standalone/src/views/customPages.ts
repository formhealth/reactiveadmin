import type { ComponentType } from 'react'
import type { Action } from '@/api/generated/model'

export type CustomPageProps = { action: Action; resource?: string; id?: string; onClose?: () => void }

// Hosts register React views under the `custom_key` of an action whose view mode is `custom`.
export const customPages: Record<string, ComponentType<CustomPageProps>> = {}

export const registerCustomPage = (key: string, component: ComponentType<CustomPageProps>) => {
  customPages[key] = component
}
