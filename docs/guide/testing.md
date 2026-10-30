# Testing

Two suites cover the React client. Storybook stories cover components in isolation (`pnpm a11y`). The crawl covers the real app against a real server: it opens every screen your manifest describes and fails on anything a person would notice.

## Crawl

The crawl signs in as an admin, reads `/api/admin/_manifest`, and visits these screens in the client:

- The home page, every menu group's overview, and every page (`register_page`) in the menu.
- Every resource's index.
- The show page of the first `--limit` records (default 2) of each resource, and the edit form of the first one.
- Every resource's new form.

Forms are rendered, never submitted. A resource that needs a parent (a required `belongs_to`) has no top-level screens, so it's listed as skipped. A resource with no records gets an index and a new form only.

Each screen must pass these checks:

- Nothing in the page says it failed: an error boundary, "Couldn't load...", "Something went wrong", or an error toast.
- The console has no errors or uncaught exceptions.
- No request fails and no API response is 4xx or 5xx, except an allowed one. A 403 `api_denied` is allowed everywhere, because a guarded resource answers it on purpose.
- axe finds no serious or critical violations. The crawl reuses the tags and rules of the story suite (`.storybook/a11yConfig.ts`), and keeps the document-level rules, because it renders whole pages.

It also records the time from navigation to the first meaningful render (the shell and the screen's content are painted, with no skeleton left). Each screen loads in a fresh browser context, so nothing is cached and times are comparable.

### Run it

```sh
pnpm crawl                                  # from the repo root, or in apps/standalone
pnpm crawl --base-url=http://localhost:5174 --resources=posts,authors --limit=1
pnpm crawl --screens=index,show --concurrency=5
pnpm crawl --headed                         # watch it
pnpm crawl --help
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--base-url` | `$CRAWL_BASE_URL`, or `http://localhost:5174` | The client to crawl. Its dev server or build must proxy `/api` to the host. |
| `--resources=a,b` | all | Only these resources' screens. Home, groups and pages are left out. |
| `--screens=index,show` | all | Only these kinds: `home`, `group`, `page`, `index`, `show`, `new`, `edit`. |
| `--limit` | 2 | Records whose show page is visited per resource. |
| `--concurrency` | 3 | Pages open at once. Keep it low against a rate-limited host. |
| `--timeout` | 20000 | Milliseconds to wait for a first meaningful render. |
| `--theme` | `light` | `light` or `dark`. |
| `--no-axe` | off | Skip accessibility checks. |
| `--headed` | off | Show the browser. |
| `--out` | `crawl-report` | Where the reports go. |

The exit code is 0 when every screen passes, 1 when any fails, and 2 when the crawl couldn't start (not signed in, no manifest, bad option).

The crawl reads records through the same API as a person would, so the host sees ordinary admin reads from the signed-in user. Use a development user.

### Report

Each run writes `crawl-report/crawl-report.json` and `crawl-report/crawl-report.md` (git-ignored). They hold a per-screen status, p50, p95 and max of the render time overall and per screen kind, and, for each failure, the URL and a short excerpt: console text, `status method path code (message)` for API responses, or the axe rule with its selectors.

Reports never contain record data. They carry resource keys, record ids, URL paths (query strings are removed, including inside messages), statuses, timings and error text cut to a couple of hundred characters. axe excerpts are rules and selectors, not page HTML. The server's error message is included for failed API calls, so keep your error messages free of sensitive data, as the gem already requires.

### Sign in

The crawl never automates a sign-in page, so it works with hosts that use SSO. It needs a session for an admin user, and takes it from either of these, which can be combined:

- `CRAWL_COOKIE`: `name=value`, or `a=1; b=2`. It's set for the base URL's host before anything runs.
- A login hook, a TypeScript module that default-exports a function. It gets the Playwright browser context and leaves it signed in. The crawl loads `--login=file` or `$CRAWL_LOGIN`, or `apps/standalone/crawl.login.ts` when that exists (git-ignored, so each developer has their own).

```ts
import type { LoginHook } from './crawl/auth.ts'

const login: LoginHook = async ({ baseUrl, context, env }) => {
  await context.addCookies([{ name: '_myapp_session', value: env.MY_APP_SESSION!, url: baseUrl }])
}

export default login
```

See `crawl/hooks/example.login.ts`. A hook can also call a test-only sign-in endpoint with `context.request.post(...)`, as `crawl/hooks/dummy.login.ts` does. The cookie must reach the API through the client's origin: the Vite proxy forwards cookies, and cookies ignore ports, so a session minted at `localhost:3003` works at `localhost:5174`.

#### Against your own app

Sign in once in a browser, or mint a session cookie with a development-only task in your app, and pass it as `CRAWL_COOKIE` (`name=value`) with the app on :3003 and the client on :5174:

```sh
export CRAWL_COOKIE="_my_app_session=..."
pnpm crawl
```

The cookie expires with your session, so mint a new one when it does. The user needs the permissions to see what you want crawled: a resource they can't index isn't in their manifest, so it isn't crawled.

### Allowlist

Put exceptions in `apps/standalone/crawl.allowlist.json` (git-ignored) or pass `--allowlist=file` or `$CRAWL_ALLOWLIST`. Every entry needs a `reason`, and its patterns are regular expressions:

```json
{
  "api": [{ "status": 404, "path": "/_options/", "code": "not_found", "reason": "an option source with no rows" }],
  "console": [{ "match": "ResizeObserver loop", "reason": "benign browser notice" }],
  "a11y": [{ "rule": "listitem", "path": "^/sketches/", "reason": "known issue in a third-party widget" }]
}
```

- `api` rules match the response `status`, and optionally its `code` (from the JSON error body) and `path`. Use them for a 404 that is expected because the data is empty. By default only 403 `api_denied` is allowed.
- `console` rules match the message of a console error or uncaught exception. The built-in list holds one entry: React 19's development-only "script tag" warning that `next-themes` triggers. The browser's own "Failed to load resource" lines are never judged, because the API check already covers them.
- `a11y` rules waive one axe rule, for screens whose path matches.

### Screenshot baselines

Off by default. `--screenshots` takes a full-page screenshot of each screen and compares it with its baseline, creating the baseline when there is none. The run fails when more than `--diff-threshold` (0.1%) of pixels differ or the size changes, and a diff image goes to `crawl-report/diffs/`. `--update-baselines` accepts the current screens as the new baselines.

Baselines live in `~/.cache/reactiveadmin-crawl/baselines/<host>` (change it with `--baseline-dir` or `$CRAWL_BASELINE_DIR`), never in git, because they show real data. Rows (`main tbody`), `<time>` and `[datetime]` elements, toasts and anything marked `data-crawl-mask` are painted over, and animations are off. Add selectors with `--mask=.some-class,#other`. Compare runs against the same dataset: the layout still follows the data, such as a longer show page for a longer record.

### Against the dummy app (CI)

`pnpm crawl:dummy` needs no running server. It seeds the gem's dummy app into a scratch sqlite database (`gem/spec/dummy/db/seeds.rb`, through `gem/spec/dummy/bin/crawl_prepare`), starts it with `rackup` on port 3098, starts Vite on port 5198 pointed at it (`RA_API_TARGET`), runs the crawl signed in through the dummy's test-only `/test/sign_in`, and stops both. It takes extra options (`pnpm crawl:dummy --resources=posts`), and `CRAWL_RAILS_PORT` and `CRAWL_VITE_PORT` move the ports. It needs `bundle install` in `gem/` and Playwright's Chromium (`pnpm exec playwright install chromium`).

The dummy's allowlist (`crawl/allowlists/dummy.json`) holds one known finding: the classic form partial for `sketches` renders a bare `<li>` outside a list.

## CI

GitHub Actions runs two workflows on pull requests and on `main`: `gem` (standardrb; `STRICT_GAPS=1 rake adapters` on Ruby 3.4 and 4.0 with sqlite and on Postgres; an ActiveAdmin 4 probe that is allowed to fail) and `client` (contract drift, types, lint, unit tests, build, Storybook build, a11y, the dummy-app crawl). `actionlint` checks the workflow files themselves.

The contract check runs `pnpm gen` and fails if the generated client differs from what is committed, so commit the output of `pnpm gen` with every change to `openapi/core.yaml`. `gem/Gemfile.lock` is committed so the gem jobs resolve the same versions every run. Dependabot updates it weekly.

Visual regression was removed for now. The crawl's [screenshot baselines](#screenshot-baselines) are the only pixel comparison.
