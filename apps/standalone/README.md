# reactiveadmin standalone

React admin that renders ActiveAdmin resources generically from the reactiveadmin JSON API (`/api/admin/*`, contract in `../../openapi/core.yaml`).

## Develop against a Rails app

Start the Rails app on :3003, sign in at <http://localhost:3003/admin> (session cookie), then:

```bash
pnpm dev   # http://localhost:5174
```

Vite proxies `/api`, `/admin`, `/assets` and `/packs` to `localhost:3003`, so the session cookie is shared.

## Production build for a Rails host

`pnpm build:host` builds the client for a host app to serve at its classic admin's URLs (`rake reactiveadmin:client:build` runs it; see `docs/guide/rollout.md`). `RA_OUT_DIR` sets where it writes, `RA_ASSET_PREFIX` the URL prefix of its files (default `/`), and `manifest.json` names the hashed entry files for the gem's shell middleware. The shell tells the client where it lives in `<meta name="reactiveadmin-config">`, and the router then sits at the classic admin's path, so `/admin/authors/123` is the same URL in both UIs. In dev there is no such tag: the router is at the root (`/authors/123`) and classic URLs are `/admin/...`. `VITE_ROUTER_BASE` and `VITE_ADMIN_PATH` change that.

Any link to a classic page that the user chose to open goes through `withClassic` (`src/lib/classic.ts`), which adds `classic=1` so the server doesn't send them back to the client.

## Develop with mocks

```bash
VITE_MOCKS=1 pnpm dev
```

MSW serves hand-written fixtures (`src/mocks/`) for contract v2: a manifest (site "Acme Admin", utility menu, resource summaries) with per-resource `_meta`, per-row permissions and actions, a full `posts` index that honors `scope`, `order`, `page`, `per_page` and `q[...]` (plus CSV export), a read-only `authors` index with tabs/columns/inline-action show pages, `content_approvals`, a `attachments` index without totals, and the `batch_operations` page.

The ladder examples mock classic HTML too (`src/mocks/classic.ts`: Formtastic and `form_with` fragments, validation re-renders, `FrameRedirect`, a CSV attachment). Iframes are navigations MSW can't intercept, so that example is a static page, `public/admin/preview_schedule.html`.

Writes are mocked too (they don't persist): session and CSRF (a stale `X-CSRF-Token` yields 422 `invalid_csrf`), create/edit forms for `posts` and `desks` (a `has_many` example) with server validation, destroy, member actions (one with a form), batch actions (one with inputs) and `_options` search.

## Forms and writes

`src/forms/` renders a `FormResponse` with react-hook-form and zod (the schema is built from the fields). Controls come from a registry, so a host can swap one: `<RecordForm fields={{ date: MyDatePicker }} />`. Params are nested from the bracketed `param` names by `paramsToObject`; the request is JSON, or multipart when a file is chosen.

`apiFetch` adds `X-CSRF-Token` (from `/admin/_session`, fetched once) to writes and retries once on `invalid_csrf`. Unsaved edits are guarded by `useBlocker`, which needs a data router (`createBrowserRouter`), so don't switch back to `<BrowserRouter>`.

Record actions (`useRecordAction`) and batch actions (`useBatchAction`) confirm, call the API, toast the result and refetch the resource's queries.

Set `VITE_SIGN_IN_URL` to change where "Sign in" links on a 401 (default `http://localhost:3003/sign_in` in dev, `/sign_in` in builds).

## Manifest and site

The manifest (`schema_version` 2) is the shell: site settings, menu and resource summaries. It never goes stale and is persisted to localStorage under the schema version and user id, so a reload paints the menu at once while `Layout` revalidates once. A different `schema_version` shows "Admin updated" with a reload button. Per-resource `ResourceMeta` (filters, scopes, action items, download formats) comes from `_meta` when a route mounts and is prefetched on menu hover or focus.

`Site` drives the brand, favicon, `document.title`, home route, the utility menu (current user, links, sign out as a CSRF-protected form for non-GET), and display: `date_format`/`datetime_format` are strftime patterns rendered through `Intl` in `site.time_zone` and `site.locale` (`src/lib/datetime.ts`).

## Fallback ladder

An action with a `view` opens in a container chosen by its `presentation` (`page` routes to `/:resource/:id/actions/:key`, `dialog` and `sheet` are overlays):

- `native`: `view.path` returns a `FormResponse`, rendered by the form renderer.
- `frame`: the classic URL is fetched with `X-Reactiveadmin-Frame: 1`, sanitized with DOMPurify (forms allowed, scripts and `on*` stripped) and styled by `src/frame/frame.css`, scoped under `.ra-frame`. Form submits and `data-method`/`data-confirm` links are intercepted (`src/frame/request.ts`): the CSRF field becomes an `X-CSRF-Token` header, `_method` and the submitter stay in the body. Responses replace the frame (HTML), toast and navigate (`FrameRedirect`) or download (attachment). Classic links to a resource map to in-app routes (`src/lib/classic.ts`); other admin URLs load in the frame. `input.datepicker` becomes the app's date picker.
- `iframe`: a same-origin `?embed=1` page that reports `reactiveadmin:resize`, `reactiveadmin:navigate` and `reactiveadmin:flash` with `postMessage`. Report the height of `body`, not `documentElement`, or the frame can never shrink.
- `custom`: register a component with `registerCustomPage(custom_key, Component)` (`src/views/customPages.ts`); without one the classic page opens in a frame.

`frame` and `iframe` nodes render the same containers inline, and `/pages/:page` renders an AA page's layout nodes.

## Sanitized HTML

`purify(html, 'display' | 'frame')` in `src/sanitize/purify.ts` is the only DOMPurify entry point. It is configured from `src/sanitize/htmlPolicy.json`, a snapshot of the gem's `ReactiveAdmin::HtmlPolicy`. After the policy changes, refresh the snapshot from a Rails app that runs the gem:

```bash
pnpm policy:sync   # runs `rake reactiveadmin:html_policy`; requires HOST_APP_PATH, the path of a Rails app that runs the gem
```

Off-site media becomes a link in display and is removed in frames; off-site form targets become `#`.

## Regenerate the client

```bash
pnpm gen
```

Writes react-query hooks and types to `src/api/generated/` from the OpenAPI contract. Don't edit them by hand.

## Storybook

```bash
pnpm storybook         # http://localhost:6006
pnpm build-storybook   # static build in storybook-static/
```

Stories live next to the code (`*.stories.tsx`). Handlers from `src/mocks/` are served by `msw-storybook-addon`; override them per story with `parameters.msw.handlers`. Set the initial URL with `parameters.route` (and `parameters.routePath` for components that read URL params). Use the toolbar to switch light and dark.

Responsive stories set their size with `parameters.viewportSize` (`{ width, height }`, default 1280 by 800), which the a11y suite applies before each story renders. Run with `TZ=UTC` (the scripts do) because dates render in local time.

Visual regression was removed for now. The crawl's `--screenshots` option still compares full-page screenshots.

## Checks

```bash
pnpm build   # tsc -b && vite build
pnpm test    # vitest: params, schema, error mapping, CSRF fetcher, strftime, classic link mapping, frame requests
pnpm lint
```

## Accessibility

```bash
pnpm a11y   # every story under axe (WCAG 2.0-2.2 A/AA + best practices), once per theme; needs `pnpm exec playwright install chromium`
```

Runs through the Storybook Vitest addon (`vitest.a11y.config.ts`, `.storybook/vitest.setup.ts`) in headless Chromium and fails on serious or critical violations; moderate and minor ones are reported only. `A11Y_REPORT=file.jsonl` writes every violation (story, theme, rule, nodes) for tallies. The `@storybook/addon-a11y` panel shows the same checks while developing.

Allowlist, kept deliberately small:

- Rules `region`, `page-has-heading-one` and `landmark-one-main` are off: stories render fragments, not documents.
- `aria-hidden-focus` ignores elements Radix marks `data-aria-hidden` while a modal is open; focus is trapped, so the hidden content is unreachable.
- Stories tagged `a11y-skip` (16) have play functions that don't run reliably under the a11y runner (iframes served by msw, toast timing). Fix the play, then drop the tag.
- Per story, `parameters.a11y.config.rules` or `parameters.a11y.disable` opt out of a rule or the whole check; add a comment saying why.

Keyboard: `Cmd/Ctrl+K` opens the page palette; arrow keys, `Home`/`End` move through the menu tree; `/` focuses the first filter, `j`/`k` move between rows, `Enter` opens the focused row.
