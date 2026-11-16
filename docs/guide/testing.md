# Testing

Two suites cover the React client. Storybook stories cover components in isolation (`pnpm a11y`). The crawl covers the real app against a real server: it opens every screen your manifest describes and fails on anything a person would notice. In your own app's request specs, [contract examples](#contract-examples) check that your registrations answer as the client expects.

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
| `--base-url` | `$CRAWL_BASE_URL`, or `http://localhost:5174` | The client to crawl. Its dev server or build must proxy `/api` to the host. A host that serves the client at its admin URLs takes that path: `https://host.example/admin`. |
| `--resources=a,b` | all | Only these resources' screens. Home, groups and pages are left out. |
| `--screens=index,show` | all | Only these kinds: `home`, `group`, `page`, `index`, `show`, `new`, `edit`. |
| `--limit` | 2 | Records whose show page is visited per resource. |
| `--concurrency` | 3 | Pages open at once. Keep it low against a rate-limited host. |
| `--timeout` | 20000 | Milliseconds to wait for a first meaningful render. |
| `--theme` | `light` | `light` or `dark`. |
| `--no-axe` | off | Skip accessibility checks. |
| `--headed` | off | Show the browser. |
| `--out` | `crawl-report` | Where the reports go. |
| `--auth=file` | see [Sign in](#sign-in) | Login hook. `--login` is the same option. |
| `--budget=[kind.]metric=ms` | none | A [performance budget](#performance-budgets). Repeatable. |
| `--budget-file=file` | none | Budgets as JSON. |
| `--parity` | off | [Compare each index](#classic-parity) with classic ActiveAdmin. |
| `--classic-path` | the base URL's path, or `/admin` | Where the classic admin lives, for `--parity`. |

The exit code is 0 when every screen passes and no budget or parity check fails, 1 when any does, and 2 when the crawl couldn't start (not signed in, no manifest, bad option).

> **Crawling real data creates audit reads.** The crawl reads records through the same API as a person would, so the host sees ordinary admin reads, and audits them, for the signed-in user. On any host with real data, sign in as a dedicated crawl user, not a person, and give it only the permissions and records you want crawled. The crawl prints a reminder when the base URL isn't local. Its own metadata requests (the manifest) are marked as background reads, but the screens and the record lookups are not.

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

### Against your own app

The crawl works against any host that runs the gem. Two setups:

- **A dev server** at `http://localhost:5174` (`pnpm dev` in `apps/standalone`, proxying `/api` and `/admin` to your app, with `RA_API_TARGET` set to your app's URL). This is the default.
- **A host serving the client at its admin URLs**, as in [Roll out the new admin](rollout.md): give the admin URL as the base URL. The crawl sets the `reactiveadmin_ui=new` cookie, so the host answers with the client. The user must be allowed to use it (`config.ui.available`), or the client sends every page back to classic and the crawl reports failures.

```sh
export CRAWL_COOKIE="_my_app_session=..."          # or --auth=./crawl.login.ts
pnpm crawl --base-url=https://staging.example.com/admin --resources=posts,authors --concurrency=2
```

The `bin` entry `reactiveadmin-crawl` in `apps/standalone` runs the same CLI (`node apps/standalone/bin/reactiveadmin-crawl.mjs --help`, or `pnpm exec reactiveadmin-crawl` after `pnpm link`). The client package isn't published, and Node doesn't run TypeScript from `node_modules`, so `npx` and `pnpm dlx` don't work yet: run it from a checkout of this repository (Node.js 24 and `pnpm exec playwright install chromium`).

Use a login hook that fits your sign-in, SSO included. The crawl never types into a sign-in page; the hook mints or loads a session for a dedicated crawl user, from a cookie, an API token exchange or a test-only endpoint. See `crawl/hooks/example.login.ts`. The hook's `baseUrl` is the origin, without the admin path.

The cookie or session expires on the host's schedule, so mint a new one when it does. The user needs the permissions to see what you want crawled: a resource they can't index isn't in their manifest, so it isn't crawled.

### Performance budgets

`--budget` fails the run when a render-time metric (`p50`, `p95` or `max`, in milliseconds) goes over its limit, either for every screen or for one kind. Repeat it for several:

```sh
pnpm crawl --budget=p95=1500 --budget=index.p95=1000 --budget=show.max=4000
```

Or keep them in a file and pass `--budget-file=crawl.budgets.json`. Flags override the file:

```json
{ "all": { "p95": 1500 }, "index": { "p95": 1000, "max": 3000 }, "show": { "p50": 600 } }
```

Kinds are `all`, `home`, `group`, `page`, `index`, `show`, `new` and `edit`. A budget fails its scope as a whole, and the report lists the screens in that scope that are over the limit, slowest first (at most ten), so a p95 violation points at the tail. A kind the run didn't crawl isn't judged. Screens that never rendered have no time and are left out of the statistics (they already fail as timeouts).

Times depend on the machine, the host's load and its data volume. Set budgets from a few runs against the same environment, with some headroom, and keep `--concurrency` the same between runs.

### Classic parity

`--parity` checks that the new index shows what the classic one shows. For each resource's index, after the React screen is checked, the crawl loads the classic page (`{classic path}/{resource}?classic=1`, signed in as the same user) and compares the first page: the number of rows and the set of record ids. A resource passes when both match. Differences, with the ids that only one side shows (at most ten each), go in the report and fail the run.

The comparison reads ids only. It never reads, compares or logs cell values.

It compares what both sides can show, so some indexes are marked `unsupported` and left out of the verdict:

- The classic page isn't a table of records the crawl can read, for example a custom index component, or a redirect to sign-in or another resource. The crawl reads each row's id from its own links, because those carry the same identifier as the React rows (a slug, say, where checkbox values are primary keys). When a row's links don't single out its own record, such as an association link beside the row's actions, the resource is reported as unsupported rather than compared on a guess.
- The React page has no `data-row-id` records. Build the client from this repository's current sources.

Both pages use the resource's default sort, filters and page size. Run it against data that is not changing: a record created between the two loads shows up as a difference. Order is ignored because rows that tie on the sort column can come back in either order.

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

CI runs it with `--parity`, so every dummy index is compared with its classic page. The `taggings` index has a custom presenter and is reported as unsupported.

## Contract examples

`ReactiveAdmin::RSpec.contract_examples` adds a request spec per registration. Each one gets the resource's meta, its index, and the show page of the first listed record, and checks every answer against `openapi/core.yaml`, the contract the client is generated from. Objects in the contract are closed for the check, so a key the contract doesn't declare fails it. Resources that only exist under a parent are left out.

Add `json_schemer` to your test group, then sign in, as a user who can read every resource, in a `before`:

```ruby
# spec/requests/reactive_admin_contract_spec.rb
require "rails_helper"
require "reactive_admin/rspec"

RSpec.describe "reactiveadmin contract", type: :request do
  before { sign_in create(:admin_user) }

  ReactiveAdmin::RSpec.contract_examples(self)
end
```

Seed at least one record per resource to cover the show pages. The same file defines a `match_contract` matcher (`expect(json).to match_contract("IndexResponse")`) for your own specs.

## Fixtures for Storybook and MSW

Hand-written mocks drift from what the API sends. `rake reactiveadmin:fixtures` records real response shapes from your app as JSON files, with the record data replaced by fakes, so your Storybook stories and MSW handlers use the payloads your admin produces.

```sh
bin/rails "reactiveadmin:fixtures[posts+authors,spec/fixtures/reactiveadmin]"
```

The arguments are the resources to record, joined with `+` (blank or `all` for every resource the user can open), and the output directory (default `tmp/reactiveadmin/fixtures`). The task renders the payloads as the user from `config.doctor_user`, the same sampling user as `rake reactiveadmin:doctor`, Database writes are blocked while it runs. It writes:

| File | Payload |
| --- | --- |
| `_manifest.json` | The manifest |
| `<resource>/meta.json` | `_meta` |
| `<resource>/index.json` | The first page of the index |
| `<resource>/show.json` | The show page of the first row |
| `<resource>/new.json`, `<resource>/edit.json` | The new form, and the edit form of the first row |

A section the user can't see or the resource doesn't have (nested under a required parent, denied by an API guard, no rows) is skipped, and the task prints why. The output names resources and sections, never values. Files of a skipped section that an earlier recording left in the directory are removed.

### What is scrubbed

Scrubbing is default deny. A string stays only when it is structural: types, keys, params, paths, enum names from your models where the payload marks a choice of that same attribute (the options of its select or filter, or a status tag in that attribute's index column or attributes-table row, unless a record holds the same text; a choice whose value is a record id is always replaced), and the labels, titles and confirmations that you wrote. Every other string is replaced with a deterministic fake of the same shape: words for text, `user12345@example.com` for an email, a valid fake date for a date, digits for a number, a UUID for a UUID, and tags kept around fake text for HTML. Numbers and JSON values are faked too. Every JSON key is replaced, in the value and its summary, so only the structure stays; distinct keys get distinct fakes.

- Ids are replaced with stable fakes, in `id` fields, refs, option values and the paths that contain them. The same record has the same fake id in every file. A numeric id stays numeric and keeps its sign.
- Masked values stay masked, and a masked form field still has no value.
- HTML inside a record value keeps only attribute names that HTML defines. Any other attribute (`data-patient-name`) is dropped. Its name and value are learned, as is the content of a dropped comment or style declaration, so text that quotes them is still scrubbed.
- Text you wrote (a label, a confirmation) is replaced when it quotes a record value found elsewhere in the payloads, wherever that value appears.
- Paths keep only the segments of your admin routes. Any other segment, such as a signed file token or a file name, is replaced; a known file extension stays. A query name stays only when the API reads it (such as `q[...]`, `scope`, `order`, `page`, `field` or `format`); any other name, and a name with no value, is replaced. Query values stay only when they are structural: a numeric `page` or `per_page`, a scope id, sort order, field name or download format that the payloads declare.
- A row's `class_name` and its actions' labels, confirmations and disabled reasons are replaced when they differ between rows. An input's `min` and `max` stay only when they're small whole numbers (up to four digits), such as a rating's 1 to 5. Those stay even when they come from a record, so don't put record data in a small numeric bound. Every other bound, a date included, is faked and learned, and the fake bounds keep their order. A field's value is then picked anywhere inside its bounds, kept or fake, on the step grid and at the value's precision (whole days for a date, minutes or seconds for a datetime), so a valid value stays valid. Nothing links the fake value to a real bound, so knowing a bound (a hard-coded `1900-01-01`) doesn't reveal the value. Kept bounds that allow only the original value (a `min` and `max` of 3) would reveal it, so they're faked too. A faked field value also fits the field's `maxlength` and `minlength`.
- HTML of a frame keeps the names of its form controls, an `<input>` with a `min` or `max` follows the same bounds rule as a form field, and a Rails `authenticity_token` is replaced with a constant.
- The same data produces the same files, so a diff shows what changed in your app, as long as the seed stays the same.
- Text with angle brackets, such as `Contact <someone@example.com>`, is treated as HTML only when it contains real HTML elements. An element name that HTML doesn't define is replaced.
- Text you wrote is scrubbed when it quotes a short value (two or three characters) only as a whole word.

Known limits of fidelity:

- A record id that equals a literal segment of your routes (an id of `posts`) is replaced everywhere it appears, including that segment, so the recorded path no longer matches your route. Telling the two apart needs route templates; record such a resource with ids that aren't route words.

Review the files before you commit them. Labels, menu entries and page text that your own code builds from record data, outside an attribute the scrubber recognizes, are structural to the scrubber and stay as they are. The task prints a warning that lists every text you wrote that it kept as is, so you can check that none of it quotes a record.

### Seed

Every fake is derived from a private seed, so nobody can work back from a fake to the value it replaced. The task reads the seed from `REACTIVEADMIN_FIXTURES_SEED`, and otherwise from `tmp/reactiveadmin_fixtures_seed`, which it creates with a random seed on the first run, readable only by you (mode `0600`). If that file is readable by others, the task warns and restricts it. Keep the seed out of your repository: `tmp/` is ignored in a Rails app, and in CI set the variable from a secret. The same seed produces the same files. To make every fake new, rotate the seed: delete the file or set a new value, then record again.

### Use them in Storybook

`fixtureHandlers` in `apps/standalone/src/mocks/fixtureHandlers.ts` turns the directory into MSW handlers for the manifest, each resource's meta, index and new form, and the recorded record's show page and edit form (everything else, such as other record ids, `_options` and `_value`, falls through to your other handlers):

```ts
import { fixtureHandlers } from './fixtureHandlers'

const files = import.meta.glob('../fixtures/reactiveadmin/**/*.json', { eager: true, import: 'default' })

export const handlers = [...fixtureHandlers(files), ...yourOtherHandlers]
```

Pass `{ base: '/my/api/admin' }` when your API isn't mounted at `/api/admin`. The handlers answer index requests with the recorded page whatever the query, so use them for how screens look, not for filtering and paging behavior.

## CI

GitHub Actions runs two workflows on pull requests and on `main`: `gem` (standardrb; `STRICT_GAPS=1` specs for every auth adapter on Ruby 4.0 with sqlite, and the default adapter on Ruby 3.4 and on Postgres; an ActiveAdmin 4 probe that is allowed to fail) and `client` (contract drift, types, lint, unit tests, build, Storybook build, a11y sharded by theme, the dummy-app crawl). `actionlint` checks the workflow files themselves.

The contract check runs `pnpm gen` and fails if the generated client differs from what is committed, so commit the output of `pnpm gen` with every change to `openapi/core.yaml`. `gem/Gemfile.lock` is committed so the gem jobs resolve the same versions every run. Dependabot updates it weekly.

Visual regression was removed for now. The crawl's [screenshot baselines](#screenshot-baselines) are the only pixel comparison.
