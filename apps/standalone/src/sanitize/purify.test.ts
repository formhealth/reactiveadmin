// @vitest-environment jsdom
import { describe, expect, it } from 'vitest'
import { filterStyle, purify } from './purify'

const parse = (html: string) => Object.assign(document.createElement('div'), { innerHTML: html })

describe('purify display', () => {
  it('strips scripts and event handlers', () => {
    expect(purify('<p onclick="x()">hi<script>alert(1)</script></p>', 'display')).toBe('<p>hi</p>')
  })

  it('swaps an off-site img for a link', () => {
    const root = parse(purify('<img src="https://cdn.example.com/a.png" alt="x">', 'display'))

    expect(root.querySelector('img')).toBeNull()
    const link = root.querySelector('a')!
    expect(link.getAttribute('href')).toBe('https://cdn.example.com/a.png')
    expect(link.textContent).toBe('External image')
    expect(link.target).toBe('_blank')
  })

  it('keeps a same-origin img with the forced attributes', () => {
    const img = parse(purify('<img src="/logo.png" referrerpolicy="origin">', 'display')).querySelector('img')!

    expect(img.getAttribute('src')).toBe('/logo.png')
    expect(img.getAttribute('referrerpolicy')).toBe('no-referrer')
    expect(img.getAttribute('loading')).toBe('lazy')
  })

  it('keeps raster data images and drops other data URLs', () => {
    const png = 'data:image/png;base64,iVBORw0KGgo='
    expect(parse(purify(`<img src="${png}">`, 'display')).querySelector('img')?.getAttribute('src')).toBe(png)
    expect(parse(purify('<img src="data:image/svg+xml;base64,PHN2Zz4=">', 'display')).querySelector('img')).toBeNull()
  })

  it('keeps a same-origin embed', () => {
    expect(parse(purify('<embed src="/doc.pdf" type="application/pdf">', 'display')).querySelector('embed')?.getAttribute('src')).toBe('/doc.pdf')
  })

  it('swaps an off-site embed for a link', () => {
    const root = parse(purify('<embed src="https://docs.example.com/a.pdf">', 'display'))

    expect(root.querySelector('embed')).toBeNull()
    expect(root.querySelector('a')?.textContent).toBe('External document')
  })

  it('drops javascript: links', () => {
    expect(parse(purify('<a href="javascript:alert(1)">x</a>', 'display')).querySelector('a')?.hasAttribute('href')).toBe(false)
  })

  it('drops class so stored markup cannot overlay the app', () => {
    expect(purify('<div class="fixed inset-0 z-50">x</div>', 'display')).toBe('<div>x</div>')
    expect(purify('<div class="fixed">x</div>', 'frame')).toBe('<div>x</div>')
  })

  it('embeds only a same-origin pdf, by declared type and path', () => {
    expect(parse(purify('<embed src="/a.html" type="text/html">', 'display')).querySelector('embed')).toBeNull()
    expect(parse(purify('<embed src="/a.pdf">', 'display')).querySelector('embed')).toBeNull()
    expect(parse(purify('<object data="/admin/authors" type="application/pdf"></object>', 'display')).querySelector('object')).toBeNull()
    expect(parse(purify('<object data="/A.PDF?x=1" type="Application/PDF"></object>', 'display')).querySelector('object')).not.toBeNull()
  })
})

describe('purify trusted media hosts', () => {
  const cdn = ['cdn.example.test']

  it('keeps images and extensionless declared pdfs from a host the manifest names', () => {
    const root = parse(purify('<img src="https://cdn.example.test/a/"><embed src="https://cdn.example.test/b/?token=x" type="application/pdf">', 'display', cdn))

    expect(root.querySelector('img')?.getAttribute('src')).toBe('https://cdn.example.test/a/')
    expect(root.querySelector('embed')).not.toBeNull()
  })

  it('still links out other hosts, undeclared types, and the same host once the call is over', () => {
    expect(parse(purify('<img src="https://evil.example/a.png">', 'display', cdn)).querySelector('img')).toBeNull()
    expect(parse(purify('<embed src="https://cdn.example.test/b/" type="text/html">', 'display', cdn)).querySelector('embed')).toBeNull()
    expect(parse(purify('<img src="https://cdn.example.test/a/">', 'display')).querySelector('img')).toBeNull()
  })

  it('keeps an extensionless same-site pdf out', () => {
    expect(parse(purify('<embed src="/b/" type="application/pdf">', 'display', cdn)).querySelector('embed')).toBeNull()
  })
})

describe('purify bypass attempts', () => {
  it.each([
    'https:evil.example.com/a.png',
    'http:/evil.example.com/a.png',
    'http:///evil.example.com/a.png',
    '/\\evil.example.com/a.png',
    '\\\\evil.example.com/a.png',
    'ht\ttps://evil.example.com/a.png',
  ])('keeps no image from %s', (src) => {
    expect(parse(purify(`<img src="${src}">`, 'display')).querySelector('img')).toBeNull()
    expect(parse(purify(`<img src="${src}">`, 'frame')).querySelector('img')).toBeNull()
  })

  it.each([
    '<a href="jav&#x09;ascript:x()">x</a>',
    '<svg><script>x()</script></svg>',
    '<math><mtext><table><mglyph><style><img src=x onerror=x()>',
    '<details open ontoggle="x()">d</details>',
    '<img srcset="https://evil.example.com/a.png 1x" src="/a.png">',
    '<base href="https://evil.example.com/">x',
  ])('neutralizes %s', (payload) => {
    for (const mode of ['display', 'frame'] as const) {
      expect(purify(payload, mode)).not.toMatch(/script|onerror|ontoggle|javascript|srcset|base|svg|math/i)
    }
  })

  it('removes a name from non-controls and a clobbering name or id from anything', () => {
    const html = purify('<input name="a"><a name="x" href="/x">l</a><button name="location">b</button><img id="cookie" src="/a.png">', 'frame')

    expect(html).toContain('name="a"')
    expect(html).not.toMatch(/name="x"|name="location"|id="cookie"/)
  })

  it('removes an off-site image button source but keeps a same-site one', () => {
    const inputs = parse(purify('<input type="image" src="https://evil.example.com/t.png"><input type="image" src="/ok.png">', 'frame')).querySelectorAll('input')

    expect(inputs[0].hasAttribute('src')).toBe(false)
    expect(inputs[1].getAttribute('src')).toBe('/ok.png')
  })
})

describe('purify frame', () => {
  it('keeps same-origin forms', () => {
    const form = parse(purify('<form action="/admin/things" method="post"><input name="q"></form>', 'frame')).querySelector('form')!

    expect(form.getAttribute('action')).toBe('/admin/things')
  })

  it('neutralizes an off-site action', () => {
    const form = parse(purify('<form action="https://evil.example.com/steal" method="post"></form>', 'frame')).querySelector('form')!

    expect(form.getAttribute('action')).toBe('#')
  })

  it('removes an off-site formaction', () => {
    const button = parse(purify('<button formaction="https://evil.example.com/steal">Go</button>', 'frame')).querySelector('button')!

    expect(button.hasAttribute('formaction')).toBe(false)
  })

  it('strips scripts, styles and targets', () => {
    expect(purify('<style>p{}</style><a href="/x" target="_top">x</a><script>1</script>', 'frame')).toBe('<a href="/x">x</a>')
  })

  it('keeps the datepicker marker on inputs only, and only for known widgets', () => {
    const root = parse(
      purify('<input class="datepicker" data-reactiveadmin-widget="date"><input data-reactiveadmin-widget="evil"><div data-reactiveadmin-widget="date"></div>', 'frame'),
    )

    expect([...root.querySelectorAll('input')].map((el) => el.getAttribute('data-reactiveadmin-widget'))).toEqual(['date', null])
    expect(root.querySelector('div')!.hasAttribute('data-reactiveadmin-widget')).toBe(false)
    expect(root.querySelector('[class]')).toBeNull()
  })

  it('removes an off-site embed rather than linking it', () => {
    const root = parse(purify('<embed src="https://docs.example.com/a.pdf">', 'frame'))

    expect(root.querySelector('embed')).toBeNull()
    expect(root.querySelector('a')).toBeNull()
  })
})

// These cases mirror gem/spec/lib/reactive_admin/html_policy_spec.rb (".style") so the two stay in step.
describe('filterStyle', () => {
  it('keeps layout declarations, normalized', () => {
    expect(filterStyle('Margin: 0  AUTO ;padding:4px 8px;display:flex;gap:.5rem;flex:1 1 0%;text-align:center')).toBe(
      'margin: 0 auto; padding: 4px 8px; display: flex; gap: .5rem; flex: 1 1 0%; text-align: center',
    )
    expect(filterStyle('margin-left:2px;width:100%;max-width:none;font-weight:700;white-space:nowrap;float:left')).toBe(
      'margin-left: 2px; width: 100%; max-width: none; font-weight: 700; white-space: nowrap; float: left',
    )
  })

  it('normalizes unit case', () => {
    expect(filterStyle('WIDTH:10PX;margin:1EM 2Rem;padding:50%')).toBe('width: 10px; margin: 1em 2rem; padding: 50%')
  })

  it.each([
    'margin-left:-2px',
    'margin:0 -1px',
    'margin:-0.5em',
    'width:100vw',
    'height:100vh',
    'width:100VW',
    'padding:1vmin',
    'margin:1vmax',
    'width:10000px',
    'margin:1cm',
    'margin:1pt',
  ])('rejects negative lengths and viewport units: %s', (css) => {
    expect(filterStyle(css)).toBe('')
  })

  it('drops properties outside the allowlist', () => {
    const css = "position:fixed;z-index:9999;opacity:0;transform:scale(9);background:red;background-color:red;content:'x';filter:blur(1px);cursor:pointer;color:red;top:0"

    expect(filterStyle(css)).toBe('')
  })

  it.each([
    'background-image:url(http://evil.test/x)',
    'width:expression(alert(1))',
    'margin:0 \\30',
    'margin: 0/**/',
    'behavior:url(x)',
    'width:calc(100% - url(x))',
    'margin:0 !important',
    'padding:10',
    'display:contents',
    'margin:1px 2px 3px 4px 5px',
    'constructor:1',
  ])('rejects %s', (css) => {
    expect(filterStyle(css)).toBe('')
  })

  it('keeps the good declarations of a mixed attribute', () => {
    expect(filterStyle('margin: 0; position: absolute; /* c */ padding: 1px; width: 10px; background: url(x); display: grid')).toBe(
      'margin: 0; width: 10px; display: grid',
    )
  })

  it('ignores broken declarations and non-ascii whitespace tricks', () => {
    expect(filterStyle(';;color;margin;:0;margin:0;\u00a0padding:0\u00a0')).toBe('margin: 0')
    expect(filterStyle('margin:\u00a00')).toBe('')
  })
})

describe('purify inline style', () => {
  it('filters style in display and frame', () => {
    expect(purify('<div style="margin:0 auto;position:fixed;color:red">x</div>', 'display')).toBe('<div style="margin: 0 auto">x</div>')
    expect(purify('<form style="padding:4px"><input style="display:block;background:url(x)"></form>', 'frame')).toBe(
      '<form style="padding: 4px"><input style="display: block"></form>',
    )
  })

  it('removes a style with nothing left', () => {
    expect(purify('<p style="position:fixed;z-index:9">x</p>', 'frame')).toBe('<p>x</p>')
  })

  it('drops negative margins and viewport-sized boxes that could cover controls', () => {
    expect(purify('<div style="margin-top:-99999px;width:100vw;height:100VH">x</div>', 'display')).toBe('<div>x</div>')
  })
})

describe('purify hostile shapes', () => {
  it('survives markup nested past the server depth cap', () => {
    expect(() => purify(`${'<div>'.repeat(500)}x`, 'display')).not.toThrow()
    expect(() => purify(`${'<div>'.repeat(500)}x`, 'frame')).not.toThrow()
  })

  it('keeps no script from a huge cell', () => {
    const html = purify(`${'<p><b>x</b><script>1</script></p>'.repeat(5000)}`, 'display')

    expect(html).not.toMatch(/script/i)
    expect(html.length).toBeGreaterThan(0)
  }, 30_000) // ~1.6s on a laptop; the 5s default is too tight for a loaded CI runner.
})
