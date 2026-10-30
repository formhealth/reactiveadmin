declare module 'pixelmatch' {
  export default function pixelmatch(
    a: Uint8Array,
    b: Uint8Array,
    output: Uint8Array | null | undefined,
    width: number,
    height: number,
    options?: { threshold?: number; includeAA?: boolean },
  ): number
}
