# Contributing

Thanks for helping. This repository has two halves that meet at one file:

| Path | What it is |
| --- | --- |
| `gem/` | The Ruby gem, plus a dummy Rails app (`gem/spec/dummy`: posts, authors, comments, tickets) that the specs and the crawl run against |
| `apps/standalone/` | The React client (Vite, TypeScript, shadcn/ui, Tailwind CSS, TanStack, React Query), its Storybook and the end-to-end crawl |
| `openapi/core.yaml` | The contract between the gem and the client |
| `docs/guide/` | User documentation |

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
| Hosted build | `RA_OUT_DIR=/tmp/host-build RA_ASSET_PREFIX=/reactiveadmin/ pnpm --filter standalone build:host` |
| Storybook | `pnpm --filter standalone storybook` (static build: `build-storybook`) |
| Accessibility (axe over every story) | `pnpm --filter standalone a11y` |
| End-to-end crawl against the dummy app | `pnpm crawl:dummy` |

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

## Report a problem

Open an issue for bugs and ideas. For a security problem, don't open an issue; see [SECURITY.md](SECURITY.md).
