import { useEffect } from 'react'
import { Link, useLocation } from 'react-router'
import { ApiError } from '@/api/fetcher'
import { Button } from '@/components/ui/button'
import { ClassicLink } from '@/components/ApiDenied'
import { isApiDenied } from '@/lib/apiDenied'
import { hosted } from '@/lib/base'
import { goClassic } from '@/lib/boot'
import { isLanding } from '@/lib/landing'
import { classicHereNow } from '@/boundaries/urls'
import { cn } from '@/lib/utils'

const SIGN_IN_URL: string =
  import.meta.env.VITE_SIGN_IN_URL ?? (import.meta.env.DEV ? 'http://localhost:3003/sign_in' : '/sign_in')

function Notice({ title, children, fullPage }: { title: string; children: React.ReactNode; fullPage?: boolean }) {
  return (
    <div role="alert" className={cn('flex items-start justify-center', fullPage ? 'min-h-screen items-center p-6' : 'py-10')}>
      <div className="w-full max-w-md rounded-lg border bg-card p-6">
        <h1 className="text-xl font-semibold">{title}</h1>
        <div className="mt-2 flex flex-col items-start gap-4 text-muted-foreground">{children}</div>
      </div>
    </div>
  )
}

// Served by a Rails host, the classic page of this URL is the way in: the host sends a signed-out user to its own sign-in.
export const SignInRequired = ({ fullPage }: { fullPage?: boolean }) => (
  <Notice title="Sign in to continue" fullPage={fullPage}>
    <p>Your session has ended or you haven't signed in yet.</p>
    <Button asChild>
      <a href={hosted ? classicHereNow() : SIGN_IN_URL}>Sign in</a>
    </Button>
  </Notice>
)

// A page the host keeps off the API. Opened by URL in a Rails host's shell, its classic page is the same URL.
function ApiDeniedNotice({ error }: { error: ApiError }) {
  const landing = isLanding(useLocation().key)
  useEffect(() => {
    if (hosted && landing) goClassic()
  }, [landing])

  return (
    <Notice title="Only available in the classic admin">
      <p>{error.message}</p>
      {error.body?.classic_url && (
        <Button asChild variant="outline">
          <ClassicLink href={error.body.classic_url}>Open in classic admin</ClassicLink>
        </Button>
      )}
    </Notice>
  )
}

type ErrorStateProps = {
  error: unknown
  label?: string
  onRetry?: () => void
  backTo?: { to: string; label: string }
}

export function ErrorState({ error, label, onRetry, backTo }: ErrorStateProps) {
  const status = error instanceof ApiError ? error.status : undefined
  const message = error instanceof Error ? error.message : 'Something went wrong'

  if (status === 401) return <SignInRequired />

  if (isApiDenied(error)) return <ApiDeniedNotice error={error} />

  if (status === 403)
    return (
      <Notice title={`You don't have access to ${label ?? 'this page'}`}>
        <p>Your account doesn't include this page. Ask an admin if you need it.</p>
      </Notice>
    )

  if (status === 404)
    return (
      <Notice title="Not found">
        <p>It may have been deleted, or the link is wrong.</p>
        {backTo && (
          <Button asChild variant="outline">
            <Link to={backTo.to}>{backTo.label}</Link>
          </Button>
        )}
      </Notice>
    )

  return (
    <Notice title={`Couldn't load ${label ?? 'this page'}`}>
      <p>{message}. Nothing was changed.</p>
      {onRetry && (
        <Button variant="outline" onClick={onRetry}>
          Try again
        </Button>
      )}
    </Notice>
  )
}
