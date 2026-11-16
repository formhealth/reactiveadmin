// Types for the preset's helpers that the client's tests import.
type Spec = Record<string, any>

export function uploadsAsMultipart(spec: Spec): Spec
export function cachePolicies(spec: Spec): Record<string, { query: { options: Record<string, unknown> } }>
export function hostOrvalConfig(options: { input: string; output: string; mutator?: string; split?: boolean }): Record<string, unknown>
