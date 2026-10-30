// Repeats get `-2`, `-3`, ... so each entry keeps its own React key (or tab value) when labels collide.
export function uniqueKeys(keys: string[]) {
  const taken = new Set<string>()
  return keys.map((key) => {
    let unique = key
    for (let n = 2; taken.has(unique); n++) unique = `${key}-${n}`
    taken.add(unique)
    return unique
  })
}
