import { useQueryClient } from '@tanstack/react-query'
import { useLocation } from 'react-router'
import { getGetRecordQueryKey, getGetResourceMetaQueryKey, useGetSession } from '@/api/generated/core'
import type { Action, ResourceMeta, ShowResponse } from '@/api/generated/model'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { DropdownMenuItem } from '@/components/ui/dropdown-menu'
import { actionRoute, classicDestination } from '@/lib/classicDestination'
import { switchUi } from '@/lib/uiMode'

// Both render nothing unless the server says this user may switch.
const useCanSwitch = () => useGetSession({ query: { staleTime: Infinity, select: (session) => session.ui?.available === true } }).data

// An action page is the client's own; its classic counterpart is the action's href, known from the click that opened the
// page or from the record or resource the page loaded.
function useSwitchToClassic() {
  const { pathname, state } = useLocation()
  const queryClient = useQueryClient()

  return () => {
    const page = actionRoute(pathname)
    const record = page?.id ? queryClient.getQueryData<ShowResponse>(getGetRecordQueryKey(page.resource, page.id))?.actions : undefined
    const meta = page && !page.id ? queryClient.getQueryData<ResourceMeta>(getGetResourceMetaQueryKey(page.resource))?.action_items : undefined
    const action: Action | undefined = state?.action ?? (record ?? meta)?.find((a) => a.key === page?.key)
    switchUi('classic', location, document, classicDestination(pathname, action))
  }
}

export function UiSwitchPanel() {
  const switchToClassic = useSwitchToClassic()
  if (!useCanSwitch()) return null

  return (
    <Card size="sm" className="mt-4 max-w-xl">
      <CardHeader>
        <CardTitle>You're using the new admin</CardTitle>
        <CardDescription>The classic admin has the same pages at the same addresses. You can switch back at any time.</CardDescription>
      </CardHeader>
      <CardContent>
        <Button variant="outline" onClick={switchToClassic}>
          Use classic admin
        </Button>
      </CardContent>
    </Card>
  )
}

export function UiSwitchMenuItem() {
  const switchToClassic = useSwitchToClassic()
  if (!useCanSwitch()) return null

  return <DropdownMenuItem onSelect={switchToClassic}>Use classic admin</DropdownMenuItem>
}
