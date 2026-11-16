# Contributing

Thanks for helping. This repository has two halves that meet at one file:

| Path | What it is |
| --- | --- |
| `gem/` | The Ruby gem, plus a dummy Rails app (`gem/spec/dummy`: posts, authors, comments, tickets) that the specs and the crawl run against |
| `apps/standalone/` | The React client (Vite, TypeScript, shadcn/ui, Tailwind CSS, TanStack, React Query), its Storybook and the end-to-end crawl |
| `gem/openapi/core.yaml` | The contract between the gem and the client, packaged with the gem (`openapi/core.yaml` links to it) |
| `docs/guide/` | User documentation |
| `apps/site/` | The project website ([VitePress](https://vitepress.dev)): a landing page, the guides and changelog (rendered from `docs/guide` and `CHANGELOG.md`), the mock-backed demo, and the client's Storybook |

## Set up

You need Ruby 3.4 or later (`.ruby-version` pins the development version), Node.js 24 (`.nvmrc`), and pnpm 8.14.1 (`corepack enable`).

```sh
pnpm install
cd gem && bundle install
```

Browser checks (accessibility, crawl) use Playwright's Chromium: `pnpm --filter standalone exec playwright install chromium`. Postgres is optional. A few specs run only when `DATABASE_URL` points at it.

## Run the checks

Run client scripts from the repository root with `pnpm --filter standalone <script>`.

| Task | Command |
| --- | --- |
| Gem specs, one authorization adapter | `cd gem && bundle exec rspec` |
| Gem specs, all three adapters | `cd gem && STRICT_GAPS=1 bundle exec rake adapters` |
| Gem lint | `cd gem && bundle exec standardrb` |
| Client unit tests | `pnpm --filter standalone test` |
| Types | `pnpm --filter standalone typecheck` |
| Lint | `pnpm --filter standalone lint` |
| Build | `pnpm build` |
| Hosted build | `RA_OUT_DIR=/tmp/host-build pnpm --filter standalone build:host` |
| Storybook | `pnpm --filter standalone storybook` (static build: `build-storybook`) |
| Accessibility (axe over every story) | `pnpm --filter standalone a11y` |
| End-to-end crawl against the dummy app | `pnpm crawl:dummy` |
| Website, with live reload | `pnpm --filter site dev` |
| Refresh the site's screenshots (with the preview running) | `pnpm --filter standalone site-screenshots` |
| Website, demo, and Storybook, as Pages serves them | `pnpm --filter site build:full && pnpm --filter site preview` (http://localhost:4173/reactiveadmin/) |

CI runs the same commands; see `.github/workflows/`. To run the client against a Rails app, see [Getting started](docs/guide/getting-started.md). Without a backend, `pnpm dev:mocks` serves fixtures from `apps/standalone/src/mocks`.

## Conventions

- **The contract.** `openapi/core.yaml` is the contract between the gem and the client. Keep it snake_case. Change the gem, the contract and the client together, and don't break the contract without updating both sides.
- **The generated client.** Never edit `apps/standalone/src/api/generated` by hand. After you change `openapi/core.yaml`, run `pnpm gen` and commit the result. CI fails when the generated client drifts from the contract.
- **ActiveAdmin internals.** Keep every access to ActiveAdmin internals inside the gem's adapter classes (`gem/lib/reactive_admin/aa`), so supporting another ActiveAdmin version touches one place.
- **Ruby.** The gem follows [Standard Ruby](https://github.com/standardrb/standard). Run `bundle exec standardrb` before you push.
- **TypeScript.** The client is TypeScript in strict mode. Build UI from the shadcn/ui primitives in `src/components/ui`, and use React Query for server state.
- **Tests and stories.** Add a spec for gem behavior (`gem/spec`), a unit test for client logic, and a Storybook story for a new component. Every story must pass the axe check in light and dark themes. Mocks, fixtures and stories use the generic publishing domain of the dummy app (authors, posts, comments, tags, tickets).
- **Sensitive data.** Don't put record data, search terms or user input in log lines, error messages, analytics or audit events. See the [security guide](docs/guide/security.md).
- **Comments.** Keep them sparse. Explain why, not what.
- **Commits.** Write concise messages, one logical change per commit.

## Release the gem

The published gem carries the prebuilt React client in `gem/vendor/client`, so a host needs no checkout and no Node.js. The directory is gitignored: it only exists in a gem you built. The client is stamped (`reactiveadmin-client.json`) with the gem version and the manifest `schema_version`, and the gem serves it only while both match. A host's `config.ui.client_assets`, then a build of its own in `public/reactiveadmin`, win over it. The build refers to its own files relatively, so it works under any `ui.asset_prefix` or CDN without a rebuild.

1. Bump `ReactiveAdmin::VERSION` in `gem/lib/reactive_admin/version.rb`, and rename the `## Unreleased` heading in `CHANGELOG.md` to `## <version>` (add a fresh `## Unreleased` above it when more work is queued). The release notes come from that section.
2. Make sure the checks above pass. Packaging fails when the client's `SCHEMA_VERSION` (`apps/standalone/src/lib/manifestCache.ts`) differs from `ReactiveAdmin::Manifest::SCHEMA_VERSION`.
3. Merge to `main`, then tag the merge commit `v<version>` and push the tag: `git tag v0.2.0 && git push origin v0.2.0`.
4. The `release` workflow does the rest. It fails unless the tag equals `v` plus `ReactiveAdmin::VERSION`, builds the client into the gem (`bundle exec rake package`, from `gem/`), installs the gem into a Gemfile that has no path to the repository and smoke-tests it (`gem/script/smoke_packaged_gem.sh`, the same check the `packaged gem` CI job runs). A maintainer then approves the `release` environment, and the workflow pushes the gem to RubyGems with trusted publishing and creates a GitHub release whose notes are the CHANGELOG section.

To rehearse without publishing, run the `release` workflow by hand (Actions, Run workflow) and leave `dry_run` on. It builds and smoke-tests the gem and stops before the publish job. To build locally, run `bundle exec rake package` in `gem/`: it writes `gem/pkg/reactiveadmin-<version>.gem`, and `rake package:client` rebuilds only the client. Check what shipped with `gem spec pkg/reactiveadmin-<version>.gem files`.

Never build a release with a plain `gem build`: it would ship without the client. Never push a gem by hand: the workflow is the only publisher.

### One-time setup

Publishing uses [RubyGems trusted publishing](https://guides.rubygems.org/trusted-publishing/), so the repository holds no API key.

1. On the GitHub repository, create an environment named `release` (Settings, Environments). Add the maintainers who may approve a publish as required reviewers, turn on **Prevent self-review**, and limit deployment to tags matching `v*`. Do this before step 2: until the environment exists, GitHub creates it unprotected on the first run, and any `v*` tag would publish with no approval.
2. On rubygems.org, open the gem's page, then Settings, Trusted publishers, and add a GitHub Actions publisher: repository owner `formhealth`, repository `reactiveadmin`, workflow `release.yml`, environment `release`. Before the first release, create it as a pending publisher (Account, Trusted publishers) for the gem name `reactiveadmin`.
3. Keep `rubygems_mfa_required` in the gemspec. Trusted publishing satisfies it.

## Report a problem

Open an issue for bugs and ideas. For a security problem, don't open an issue; see [SECURITY.md](SECURITY.md).
