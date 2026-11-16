import { useState, type ReactNode } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { useHotkeys } from '@/hooks/useHotkeys'
import { anywhere, ScopeContext } from '@/hooks/useShortcutScope'
import { modKey } from '@/lib/platform'
import { available, keyGlyph, type Shortcut } from '@/lib/shortcuts'

const Keys = ({ shortcut }: { shortcut: Shortcut }) => (
  <span className="flex items-center gap-1.5">
    {shortcut.keys.map((key, i) => (
      <span key={key} className="flex items-center gap-1.5">
        {i > 0 && <span className="text-muted-foreground">or</span>}
        <kbd className="rounded-sm border px-1.5 font-mono text-xs">
          {shortcut.mod && modKey}
          {keyGlyph(key)}
        </kbd>
      </span>
    ))}
  </span>
)

export function ShortcutsProvider({ children }: { children: ReactNode }) {
  const [scope, setScope] = useState(anywhere)
  const [open, setOpen] = useState(false)
  useHotkeys({ help: () => setOpen(true) })

  return (
    <ScopeContext value={setScope}>
      {children}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent aria-describedby={undefined}>
          <DialogHeader>
            <DialogTitle>Keyboard shortcuts</DialogTitle>
          </DialogHeader>
          <ul className="flex flex-col gap-2">
            {available(scope.screen, scope.caps).map((shortcut) => (
              <li key={shortcut.id} className="flex items-center justify-between gap-4">
                <span>{shortcut.label}</span>
                <Keys shortcut={shortcut} />
              </li>
            ))}
          </ul>
        </DialogContent>
      </Dialog>
    </ScopeContext>
  )
}
