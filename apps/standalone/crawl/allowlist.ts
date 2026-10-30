import { existsSync, readFileSync } from 'node:fs'

export type ApiRule = { status: number; code?: string; path?: string; reason: string }
export type ConsoleRule = { match: string; reason: string }
export type A11yRule = { rule: string; path?: string; reason: string }
export type Allowlist = { api: ApiRule[]; console: ConsoleRule[]; a11y: A11yRule[] }

// A guarded resource answers 403 `api_denied` on purpose; the client shows where to go instead.
export const DEFAULT_ALLOWLIST: Allowlist = {
  api: [{ status: 403, code: 'api_denied', reason: 'an api guard reserves this page for the classic admin' }],
  console: [{ match: '^Encountered a script tag while rendering React component', reason: "next-themes' inline script; React 19 warns in development builds only" }],
  a11y: [],
}

export const mergeAllowlists = (...lists: Partial<Allowlist>[]): Allowlist => ({
  api: lists.flatMap((l) => l.api ?? []),
  console: lists.flatMap((l) => l.console ?? []),
  a11y: lists.flatMap((l) => l.a11y ?? []),
})

export function loadAllowlist(file: string | undefined): Allowlist {
  if (!file || !existsSync(file)) return DEFAULT_ALLOWLIST
  return mergeAllowlists(DEFAULT_ALLOWLIST, JSON.parse(readFileSync(file, 'utf8')) as Partial<Allowlist>)
}

export type ApiResponse = { status: number; path: string; code?: string }

export const apiAllowed = ({ status, path, code }: ApiResponse, rules: ApiRule[]) =>
  rules.some((r) => r.status === status && (!r.code || r.code === code) && (!r.path || new RegExp(r.path).test(path)))

export const consoleAllowed = (text: string, rules: ConsoleRule[]) => rules.some((r) => new RegExp(r.match).test(text))

export const a11yAllowed = (rule: string, path: string, rules: A11yRule[]) => rules.some((r) => r.rule === rule && (!r.path || new RegExp(r.path).test(path)))
