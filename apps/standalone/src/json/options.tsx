import type { CustomButtonDefinition, CustomNodeDefinition, OnCopyFunction } from 'json-edit-react'
import { Link2 } from 'lucide-react'
import { toast } from 'sonner'
import { Masked } from '@/components/Masked'
import { pathString } from './paths'
import { jsonTheme } from './theme'
import { MASKED } from './tree'

export const copyText = (text: string, done: string) =>
  navigator.clipboard?.writeText(text).then(
    () => toast.success(done),
    () => toast.error("Couldn't copy to the clipboard"),
  ) ?? toast.error("Couldn't copy to the clipboard")

export const onCopy: OnCopyFunction = ({ success, type }) => (success ? toast.success(type === 'path' ? 'Path copied' : 'Value copied') : toast.error("Couldn't copy to the clipboard"))

export const maskedNode: CustomNodeDefinition = {
  condition: ({ value }) => value === MASKED,
  component: Masked,
  showOnEdit: false,
  showEditTools: false,
}

const copyPathButton: CustomButtonDefinition = {
  label: 'Copy path',
  Element: () => <Link2 className="size-3.5" aria-hidden />,
  onClick: ({ path }, e) => {
    e.stopPropagation()
    copyText(pathString(path), 'Path copied')
  },
}

export const treeButtons = [copyPathButton]

// Props the viewer and the editor share.
export const treeProps = {
  theme: jsonTheme,
  rootName: '',
  showCollectionCount: true,
  showStringQuotes: true,
  showIconTooltips: true,
  minWidth: 0,
  maxWidth: '100%',
  indent: 3,
}


