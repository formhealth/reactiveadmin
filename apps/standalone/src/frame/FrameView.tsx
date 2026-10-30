import { useEffect, useEffectEvent, useId, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, CircleAlert, ExternalLink } from 'lucide-react'
import { createPortal } from 'react-dom'
import { useNavigate } from 'react-router'
import { toast } from 'sonner'
import { csrfToken, resetCsrf } from '@/api/fetcher'
import type { FrameRedirect } from '@/api/generated/model'
import { DatePicker } from '@/components/DatePicker'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogTitle } from '@/components/ui/alert-dialog'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { useMapClassic } from '@/hooks/useManifest'
import { isAdminPath, sameOrigin } from '@/lib/classic'
import { invalidateData, routeFor } from '@/lib/records'
import { cn } from '@/lib/utils'
import { purify, WIDGET_ATTRIBUTE } from '@/sanitize/purify'
import { nameUnlabeledControls } from './names'
import { buildFrameRequest, buildLinkRequest, classicLink, filenameOf, sameTitle, type FrameRequest } from './request'
import './frame.css'

const FIELD = ':is(input,select,textarea):not([type=hidden]):not([hidden])'

function focusFirst(root: HTMLElement) {
  const target = root.querySelector<HTMLElement>(`.error ${FIELD}, .error [data-ra-date] button`) ?? root.querySelector<HTMLElement>(`${FIELD}, [data-ra-date] button`)
  ;(target ?? root).focus()
}

type Picker = { input: HTMLInputElement; host: HTMLElement }

function setNativeValue(input: HTMLInputElement, value: string) {
  input.value = value
  input.dispatchEvent(new Event('input', { bubbles: true }))
}

// Classic datepicker inputs (marked by the server, since frames carry no classes) are swapped for ours. The original input stays (hidden) so the form posts it unchanged.
function DateWidget({ input }: { input: HTMLInputElement }) {
  const [value, setValue] = useState(input.value)
  const id = useId()
  const label = input.labels?.[0]
  // The accessible name has to contain the visible date, so it is the classic label followed by the button's own text.
  if (label) label.id ||= `${id}-label`
  return (
    <DatePicker
      id={id}
      value={value}
      aria-labelledby={label ? `${label.id} ${id}` : undefined}
      aria-label={label ? undefined : 'Date'}
      aria-required={input.required || undefined}
      clearable={!input.required}
      onChange={(day) => {
        setValue(day)
        setNativeValue(input, day)
      }}
    />
  )
}

type FrameViewProps = {
  src?: string
  // Server-rendered markup to show instead of fetching `src`.
  html?: string
  title?: string | null
  // Moves focus into the content on first paint too, not just after swaps.
  autoFocus?: boolean
  // Drops the card chrome, for frames that already sit in a dialog or sheet.
  bare?: boolean
  // Called before the frame navigates the app elsewhere (so a hosting overlay can close).
  onLeave?: () => void
}

type Confirm = { message: string; label: string; destructive: boolean; run: () => void }

export function FrameView({ src, html: initial, title, autoFocus, bare, onLeave }: FrameViewProps) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const mapUrl = useMapClassic()
  const root = useRef<HTMLDivElement>(null)
  const swapped = useRef(false)
  const requested = useRef<string>(undefined)
  const [stack, setStack] = useState<string[]>(src ? [src] : [])
  const [markup, setMarkup] = useState(initial)
  const [failed, setFailed] = useState(false)
  const [busy, setBusy] = useState(false)
  const [confirming, setConfirming] = useState<Confirm>()
  const [pickers, setPickers] = useState<Picker[]>([])

  const current = stack.at(-1)
  const base = new URL(current ?? '', globalThis.location.href).href
  const clean = useMemo(() => (markup == null ? undefined : purify(markup, 'frame')), [markup])

  const exchange = async ({ url, init }: FrameRequest, retried = false): Promise<Response> => {
    const write = init.method !== 'GET'
    const headers = { ...(init.headers as Record<string, string>), ...(write && { 'X-CSRF-Token': await csrfToken() }) }
    const res = await fetch(url, { credentials: 'include', ...init, headers })
    if (write && !retried && res.status === 422 && res.headers.get('content-type')?.includes('json')) {
      if ((await res.clone().json().catch(() => null))?.code === 'invalid_csrf') {
        resetCsrf()
        return exchange({ url, init }, true)
      }
    }
    return res
  }

  const download = async (res: Response) => {
    const link = Object.assign(document.createElement('a'), { href: URL.createObjectURL(await res.blob()), download: filenameOf(res.headers.get('content-disposition')) ?? 'download' })
    link.click()
    setTimeout(() => URL.revokeObjectURL(link.href), 1000)
  }

  const redirect = ({ redirect: location, flash }: FrameRedirect): Promise<void> | void => {
    Object.entries(flash ?? {}).forEach(([kind, message]) => (/alert|error/.test(kind) ? toast.error(message) : toast.success(message)))
    invalidateData(queryClient)
    const to = routeFor(location) || mapUrl(location.url)
    if (to) {
      onLeave?.()
      return navigate(to)
    }
    // Another classic page: stay in the frame rather than popping a tab.
    const next = buildLinkRequest(location.url, 'get', base)
    if (next && isAdminPath(sameOrigin(location.url)?.pathname ?? '')) return send(next)
    window.open(location.url, '_blank', 'noopener,noreferrer')
  }

  const send = async (request: FrameRequest, push = true): Promise<void> => {
    setBusy(true)
    try {
      const res = await exchange(request)
      const type = res.headers.get('content-type') ?? ''
      if (res.headers.get('content-disposition')?.startsWith('attachment')) return await download(res)
      if (type.includes('json')) {
        const body = await res.json().catch(() => ({}))
        if (body.redirect) return redirect(body)
        throw new Error(body.message ?? `Request failed (${res.status})`)
      }
      // A page that rejects a submit (422) is still the page to show, with its inline errors.
      if (!type.includes('html')) throw new Error(`Request failed (${res.status})`)
      setMarkup(await res.text())
      setFailed(false)
      if (push && res.ok && request.init.method === 'GET') setStack((s) => [...s, request.url])
    } catch (error) {
      if (markup == null) setFailed(true)
      else toast.error(error instanceof Error ? error.message : 'Something went wrong')
    } finally {
      setBusy(false)
    }
  }

  const loadInitial = useEffectEvent((url: string) => send(buildLinkRequest(url, 'get', base)!, false))
  useEffect(() => {
    if (initial != null || !src || requested.current === src) return
    requested.current = src
    setFailed(false)
    loadInitial(src)
  }, [src, initial])

  useLayoutEffect(() => {
    const host = root.current
    if (!host) return
    host.querySelectorAll<HTMLElement>('#title_bar, #page_title, .page_title').forEach((el) => (el.hidden = true))
    const heading = host.querySelector<HTMLElement>('h1, h2, h3')
    if (heading && sameTitle(heading.textContent, title)) heading.hidden = true
    nameUnlabeledControls(host)
    setPickers(
      [...host.querySelectorAll<HTMLInputElement>(`input[${WIDGET_ATTRIBUTE}="date"]`)].map((input) => {
        const span = Object.assign(document.createElement('span'), { className: 'ra-date' })
        span.dataset.raDate = ''
        input.before(span)
        input.hidden = true
        return { input, host: span }
      }),
    )
  }, [clean, title])

  useEffect(() => {
    if (clean == null) return
    const first = !swapped.current
    swapped.current = true
    if (!first || autoFocus) requestAnimationFrame(() => root.current && focusFirst(root.current))
  }, [clean, autoFocus])

  const confirmed = (message: string | undefined, label: string, destructive: boolean, run: () => void) => (message ? setConfirming({ message, label, destructive, run }) : run())

  const followLink = (href: string, method: string) => {
    const target = sameOrigin(href, base)
    if (!target) return void window.open(href, '_blank', 'noopener,noreferrer')
    if (method.toLowerCase() === 'get') {
      const to = mapUrl(target.pathname + target.search)
      if (to) return navigate(to)
      if (!isAdminPath(target.pathname)) return void window.open(href, '_blank', 'noopener')
    }
    send(buildLinkRequest(href, method, base)!)
  }

  const onClick = (e: React.MouseEvent) => {
    const link = (e.target as Element).closest('a')
    const href = link?.getAttribute('href')
    if (!link || !href || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    if (href.startsWith('#') || /^(mailto|tel):/i.test(href) || link.hasAttribute('download')) return
    e.preventDefault()
    confirmed(link.dataset.confirm, link.textContent?.trim() || 'Continue', link.dataset.method === 'delete', () => followLink(href, link.dataset.method ?? 'get'))
  }

  const onSubmit = (e: React.FormEvent) => {
    const form = e.target
    if (!(form instanceof HTMLFormElement) || e.defaultPrevented) return
    e.preventDefault()
    const submitter = (e.nativeEvent as SubmitEvent).submitter
    const attr = (name: string, formName = name) => submitter?.getAttribute(`form${name}`) ?? form.getAttribute(formName)
    const request = buildFrameRequest({ action: attr('action'), method: attr('method'), enctype: attr('enctype'), data: new FormData(form, submitter), base })
    if (!request) return void toast.error("That form can't be sent from here")
    confirmed(submitter?.dataset.confirm ?? form.dataset.confirm, (submitter as HTMLInputElement | null)?.value || 'Continue', request.init.body instanceof URLSearchParams && request.init.body.get('_method') === 'delete', () => send(request, false))
  }

  const back = () => {
    const previous = stack.at(-2)
    if (!previous) return
    setStack(stack.slice(0, -1))
    send(buildLinkRequest(previous, 'get', base)!, false)
  }

  const classicHref = current && classicLink(current)

  return (
    <section aria-label={title ?? 'Classic page'} aria-busy={busy} className={cn('flex min-w-0 flex-col', !bare && 'rounded-lg border bg-card')}>
      <div className={cn('min-h-12', !bare && 'p-4', busy && 'opacity-60 transition-opacity')}>
        {failed ? (
          <Alert variant="destructive">
            <CircleAlert />
            <AlertTitle>Couldn't load this page</AlertTitle>
            <AlertDescription>
              <Button variant="outline" size="sm" className="mt-1" onClick={() => current && send(buildLinkRequest(current, 'get', base)!, false)}>
                Try again
              </Button>
            </AlertDescription>
          </Alert>
        ) : clean == null ? (
          <div className="flex flex-col gap-3" aria-hidden>
            {[60, 90, 75].map((w) => (
              <Skeleton key={w} className="h-5" style={{ width: `${w}%` }} />
            ))}
          </div>
        ) : (
          <div ref={root} tabIndex={-1} className="ra-frame" onClick={onClick} onSubmit={onSubmit} dangerouslySetInnerHTML={{ __html: clean }} />
        )}
      </div>
      {(stack.length > 1 || classicHref) && (
        <footer className={cn('flex items-center justify-between gap-3 text-xs text-muted-foreground', bare ? 'pt-2' : 'border-t px-4 py-2')}>
          {stack.length > 1 ? (
            <Button variant="ghost" size="xs" onClick={back}>
              <ArrowLeft />
              Back
            </Button>
          ) : (
            <span />
          )}
          {classicHref && (
            <a href={classicHref} className="inline-flex items-center gap-1 underline-offset-4 hover:underline">
              Open in classic admin
              <ExternalLink className="size-3" aria-hidden />
            </a>
          )}
        </footer>
      )}
      {pickers.map((p) => createPortal(<DateWidget input={p.input} />, p.host))}
      <AlertDialog open={!!confirming} onOpenChange={(open) => !open && setConfirming(undefined)}>
        <AlertDialogContent>
          <AlertDialogTitle>{confirming?.label}</AlertDialogTitle>
          <AlertDialogDescription>{confirming?.message}</AlertDialogDescription>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction variant={confirming?.destructive ? 'destructive' : 'default'} onClick={() => confirming?.run()}>{confirming?.label}</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </section>
  )
}
