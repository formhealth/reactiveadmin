const CONTROLS = 'input:not([type=hidden],[type=submit],[type=button],[type=reset],[type=image]), select, textarea'

// `plan[starts_on]` reads as "Starts on".
const humanize = (name: string) => {
  const words = (name.match(/[^[\]]+/g)?.at(-1) ?? '').replace(/_/g, ' ').trim()
  return words.charAt(0).toUpperCase() + words.slice(1)
}

// Classic pages can render a control with no label (a bare `select_tag`). Frames show them as they are, so the name
// the field already carries stands in, which keeps it from being announced as an anonymous control.
export function nameUnlabeledControls(root: ParentNode) {
  for (const control of root.querySelectorAll<HTMLInputElement>(CONTROLS)) {
    if (control.labels?.length || control.title || control.hasAttribute('aria-label') || control.hasAttribute('aria-labelledby')) continue
    const name = control.getAttribute('placeholder') || humanize(control.name || control.id)
    if (name) control.setAttribute('aria-label', name)
  }
}
