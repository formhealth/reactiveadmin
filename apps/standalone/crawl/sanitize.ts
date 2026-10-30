// Reports carry resource keys, ids and paths, never query values or record data.
export const stripQuery = (url: string, home?: string) => {
  try {
    const { origin, pathname } = new URL(url, 'http://local.invalid')
    return origin === 'http://local.invalid' || origin === home ? pathname : `${origin}${pathname}`
  } catch {
    return url.split(/[?#]/)[0]
  }
}

export const truncate = (text: string, max = 200) => {
  const flat = text.replace(/\s+/g, ' ').trim()
  return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat
}

export const scrub = (text: string, max = 200, home?: string) => truncate(text.replace(/https?:\/\/[^\s"'<>)]+/g, (url) => stripQuery(url, home)), max)
