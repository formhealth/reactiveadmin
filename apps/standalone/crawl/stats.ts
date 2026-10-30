// Nearest-rank percentile of an unsorted sample.
export const percentile = (values: number[], p: number) => {
  if (!values.length) return undefined
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)]
}

export type Timing = { n: number; p50?: number; p95?: number; max?: number }

export const timing = (values: number[]): Timing => ({
  n: values.length,
  p50: percentile(values, 50),
  p95: percentile(values, 95),
  max: percentile(values, 100),
})
