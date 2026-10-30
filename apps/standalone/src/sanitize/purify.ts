import DOMPurify, { type Config } from 'dompurify'
import snapshot from './htmlPolicy.json'

// Mirrors `ReactiveAdmin::HtmlPolicy`. Regenerate with `pnpm policy:sync`, never by hand.
type Media = { attribute: string }
type Side = { tags: string[]; attributes: string[]; uri_schemes: string[]; trusted_hosts: string[] }
type Policy = {
  version: number
  style: { properties: Record<string, string>; forbidden_values: string[] }
  display: Side & { media: Record<string, Media>; embed: { types: string[]; extensions: string[] } }
  frame: Side & {
    removed_tags: string[]
    same_origin_attributes: string[]
    named_tags: string[]
    clobbered_names: string[]
    widget_attribute: string
    widgets: Record<string, string>
    forced_attributes: Record<string, Record<string, string>>
  }
}

export type Mode = 'display' | 'frame'

const { display, frame, style } = snapshot as Policy

const DATA_IMAGE = /^data:image\/(?:png|jpe?g|gif|webp|bmp);base64,[a-z0-9+/=\s]+$/i
const EXTERNAL = /^(?:https?:)?\/\/\S+$/i
const EXTERNAL_LABEL: Record<string, string> = { img: 'External image', embed: 'External document', object: 'External document', iframe: 'External page' }
// Anything outside printable ASCII (or a backslash) is never same-site: the server's URI parse rejects it too.
const UNSAFE_URL_CHARS = /[^\x21-\x7e]|\\/
const SCHEME = /^[a-z][a-z0-9+.-]*:/i
const EDGE_ASCII_SPACE = /^[\0\t\n\v\f\r ]+|[\0\t\n\v\f\r ]+$/g
export const WIDGET_ATTRIBUTE = frame.widget_attribute
const CLOBBERED = frame.clobbered_names.map((name) => name.toLowerCase())

// The same scheme list the server checks, with DOMPurify's relative-URL rules; data: is handled per tag below.
const uriRegex = (schemes: string[]) => new RegExp(`^(?:(?:${schemes.join('|')}):|[^a-z]|[a-z+.-]+(?:[^a-z+.:-]|$))`, 'i')

const STYLE_PATTERNS = new Map(Object.entries(style.properties).map(([name, pattern]) => [name, new RegExp(`^(?:${pattern})$`)]))
// ASCII-only whitespace on purpose: the server trims exactly the same characters.
const tidy = (text: string) => text.toLowerCase().replace(/[ \t\r\n\f]+/g, ' ').replace(/^ | $/g, '')

// Same rules as `ReactiveAdmin::HtmlPolicy.style`: layout declarations only, never anything that loads or overlays.
export function filterStyle(css: string): string {
  return css
    .split(';')
    .flatMap((declaration) => {
      const colon = declaration.indexOf(':')
      if (colon < 0) return []
      const property = tidy(declaration.slice(0, colon))
      const value = tidy(declaration.slice(colon + 1))
      const allowed = STYLE_PATTERNS.get(property)?.test(value) && !style.forbidden_values.some((forbidden) => value.includes(forbidden))
      return allowed ? [`${property}: ${value}`] : []
    })
    .join('; ')
}

const configs: Record<Mode, Config> = {
  display: {
    ALLOWED_TAGS: display.tags,
    ALLOWED_ATTR: display.attributes,
    ALLOWED_URI_REGEXP: uriRegex(display.uri_schemes),
    ALLOW_DATA_ATTR: false,
  },
  frame: {
    ALLOWED_TAGS: frame.tags,
    ALLOWED_ATTR: frame.attributes,
    ALLOWED_URI_REGEXP: uriRegex(frame.uri_schemes),
    // Stricter than the server: a frame must not style the page or retarget its own navigation.
    FORBID_TAGS: [...frame.removed_tags, 'style', 'link', 'meta'],
    FORBID_ATTR: ['target', 'formtarget'],
    ALLOW_DATA_ATTR: false,
  },
}

// The host's trusted media hosts for the call in progress (the manifest's `site.trusted_media_hosts`), on top of the snapshot.
let runtimeHosts: readonly string[] = []
const trustedHost = (hostname: string) => [...display.trusted_hosts, ...runtimeHosts].some((host) => host.toLowerCase() === hostname)

// Mirrors `HtmlPolicy.same_origin?`: a scheme needs a host, and `//` is protocol-relative.
function sameOrigin(value: string) {
  const url = value.replace(EDGE_ASCII_SPACE, '')
  if (UNSAFE_URL_CHARS.test(url)) return false
  if (SCHEME.test(url) ? !/^https?:\/\/[^/?#]/i.test(url) : url.startsWith('//')) return false

  let parsed: URL
  try {
    parsed = new URL(url, location.href)
  } catch {
    return false
  }
  return (
    /^https?:$/.test(parsed.protocol) &&
    (parsed.host === location.host || trustedHost(parsed.hostname))
  )
}

// Mirrors `HtmlPolicy.pdf?`: a same-site embed must declare a PDF type and have a .pdf path; a trusted host's signed
// links have no extension, so its declared type is enough.
function isSafeEmbed(node: Element, url: string) {
  const path = url.split(/[?#]/)[0].toLowerCase()
  const trusted = /^https?:\/\//i.test(url) && trustedHost(new URL(url, location.href).hostname)
  return display.embed.types.includes(tidy(node.getAttribute('type') ?? '')) && (trusted || display.embed.extensions.some((ext) => path.endsWith(ext)))
}

function loadable(node: Element, tag: string, url: string) {
  if (tag === 'img') return DATA_IMAGE.test(url) || sameOrigin(url)
  if (tag === 'embed' || tag === 'object') return sameOrigin(url) && isSafeEmbed(node, url)
  return sameOrigin(url)
}

function externalLink(node: Element, href: string) {
  const link = node.ownerDocument.createElement('a')
  Object.assign(link, { href, target: '_blank', rel: 'noopener noreferrer', textContent: EXTERNAL_LABEL[node.localName] })
  return link
}

// Runs after DOMPurify has filtered attributes, so it only has to decide where each surviving URL may point.
function enforce(node: Element, mode: Mode) {
  const tag = node.localName

  // DOMPurify lets any data: URL through on img, so the raster check here is what keeps SVG out.
  const media = display.media[tag]
  if (media) {
    const url = node.getAttribute(media.attribute) ?? ''
    if (!loadable(node, tag, url)) {
      if (mode === 'display' && EXTERNAL.test(url)) return node.replaceWith(externalLink(node, url))
      return node.remove()
    }
  }

  if (tag === 'input' && node.hasAttribute('src') && !sameOrigin(node.getAttribute('src') ?? '')) node.removeAttribute('src')

  for (const name of frame.same_origin_attributes) {
    const value = node.getAttribute(name)
    if (value != null && !sameOrigin(value)) node.setAttribute(name, '#')
  }

  // Named access on document and form elements shadows their own properties, so a clobbering name is removed.
  for (const attr of ['name', 'id'] as const) {
    const value = node.getAttribute(attr)
    if (value == null) continue
    if ((attr === 'name' && !frame.named_tags.includes(tag)) || CLOBBERED.includes(value.toLowerCase())) node.removeAttribute(attr)
  }

  // The server sets the marker from a fixed table; a value outside it is dropped here too.
  const widget = node.getAttribute(WIDGET_ATTRIBUTE)
  if (widget != null && !(widget in frame.widgets && tag === 'input')) node.removeAttribute(WIDGET_ATTRIBUTE)

  if (tag !== 'img') {
    node.removeAttribute('referrerpolicy')
    node.removeAttribute('loading')
  }
  for (const [name, value] of Object.entries(frame.forced_attributes[tag] ?? {})) node.setAttribute(name, value)
}

const instances = {
  display: DOMPurify(),
  frame: DOMPurify(),
}
for (const instance of Object.values(instances)) {
  instance.addHook('uponSanitizeAttribute', (_node, data) => {
    if (data.attrName !== 'style') return
    data.attrValue = filterStyle(data.attrValue)
    if (!data.attrValue) data.keepAttr = false
  })
}
instances.display.addHook('afterSanitizeAttributes', (node) => enforce(node, 'display'))
instances.frame.addHook('afterSanitizeAttributes', (node) => enforce(node, 'frame'))

export function purify(html: string, mode: Mode, trustedHosts: readonly string[] = []): string {
  runtimeHosts = trustedHosts
  try {
    return instances[mode].sanitize(html, configs[mode])
  } finally {
    runtimeHosts = []
  }
}
