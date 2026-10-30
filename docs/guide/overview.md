# Overview

reactiveadmin turns the ActiveAdmin registrations you already have into a JSON API, an OpenAPI description, a React admin client, and a Model Context Protocol (MCP) server for AI agents. Your `app/admin` files stay the single source of truth. You don't write serializers, API controllers, or frontend pages per resource.

This page explains why the project exists, which parts of ActiveAdmin it reuses, what it replaces, what you can add on top, and where it stops.

## Why reactiveadmin exists

ActiveAdmin is a productive way to build back-office screens in Rails, and large apps accumulate a lot of it. Over the years, a mature app's registrations (resources and pages) come to encode a great deal of operational knowledge: filters, scopes, forms, custom actions, and authorization rules.

That investment is locked inside ActiveAdmin's server-rendered views:

- **The UI is dated and hard to change.** Pages are Arbre and ERB templates with jQuery-era JavaScript and Sass. Modern patterns, such as typeaheads, inline editing, keyboard navigation, and dark mode, are expensive to add.
- **There's no API.** Other apps, scripts, and agents can't use the admin's logic without scraping HTML or duplicating it.
- **It can't be embedded.** The admin can't live inside another product, such as a customer-facing dashboard, with that product's navigation.
- **Rewriting is risky.** Rebuilding every screen by hand would duplicate business rules, drift from the original, and take months.

reactiveadmin takes a different path: keep ActiveAdmin as the definition of each screen and of who may use it, and generate everything else from that definition. Migration becomes incremental. Every screen works on day one, and each one improves as the gaps close.

## What reactiveadmin reuses from ActiveAdmin

reactiveadmin runs inside ActiveAdmin rather than beside it. The API redraws ActiveAdmin's routes under a mount path (for example, `/api/admin`) and answers through ActiveAdmin's own controllers. As a result, you keep the following without changes:

- **Registrations and the DSL.** `ActiveAdmin.register`, `register_page`, `index`, `show`, `form`, `filter`, `scope`, `action_item`, `member_action`, `collection_action`, `batch_action`, `permit_params`, `belongs_to`, and `menu`.
- **Controllers and their overrides.** `scoped_collection`, `find_resource`, `build_new_resource`, custom `create`, `update`, and `destroy`, and `before_action` callbacks run as they do today.
- **Querying.** ActiveAdmin's collection pipeline handles filtering (Ransack), scoping, sorting, and pagination, so results match the classic pages exactly.
- **Authorization.** Your ActiveAdmin authorization adapter (Pundit, for example) decides every read, write, and action. reactiveadmin adds no second permission system.
- **Authentication.** The default adapter uses ActiveAdmin's `authentication_method` and `current_user_method`, including CSRF protection.
- **Forms.** Formtastic forms are recorded into typed form schemas, including `has_many` nested attributes, `fields_for`, and option collections.
- **Show pages.** Arbre component trees (`attributes_table`, `panel`, `table_for`, `tabs`, `columns`, and `status_tag`) are read as typed nodes instead of HTML.
- **Classic HTML as a fallback.** Any view reactiveadmin can't represent natively still renders, either as sanitized HTML inline or as the classic page in a frame.

Because the same code paths serve both UIs, a read through the API returns the same records the classic page shows, and a write produces the same database change. The gem's specs check this against the dummy app's resources, and you can run the same comparison against your own.

## What reactiveadmin replaces

reactiveadmin replaces ActiveAdmin's presentation layer and adds the interfaces ActiveAdmin never had.

| ActiveAdmin today | reactiveadmin |
| --- | --- |
| Arbre and ERB views, Sass, and jQuery | A React client built with Vite, TypeScript, Tailwind CSS, shadcn/ui, TanStack Table, and React Query |
| Full page loads for every filter, sort, and save | Client-side navigation with real URLs, cached data, and optimistic form state |
| HTML only | A JSON API (`application/vnd.reactiveadmin+json`) with a generated OpenAPI 3.1 document |
| No agent access | An MCP server whose tools call the same API, so agents act as a signed-in admin |
| Hand-maintained menus | A menu overlay DSL that arranges resources into an information architecture |
| `datalist` helpers | Declared option sources that power typeaheads in forms and filters |
| Free-form ActiveAdmin HTML in the API | A strict HTML policy: only DSL-rendered controls become actions, and stored data never does |

The classic UI keeps working. Hosts choose per request which UI to render, so you can roll the new UI out gradually.

## Capabilities you can enable

The following capabilities build on the API. Each one is opt-in through configuration or the registration DSL.

### Rollout and routing

- **Same URLs in both UIs.** `/admin/authors/123` opens the same page in classic and in React. The host decides which to render from a cookie the admin sets, and from `config.ui` settings (see [Rolling out the new admin](rollout.md)).
- **A per-admin toggle.** Admins switch between UIs from the dashboard, and `?classic=1` opens any page in classic for one request.
- **Embedding.** The client is designed to render inside a host app's own layout and navigation, at the same `/admin` paths.

### Security

- **Explicit exposure.** With `config.expose = :listed`, only resources you place in the menu overlay are served.
- **API guards.** `api false`, `api :deny`, `api :read_only`, `api :session_only`, and registered custom guards keep sensitive actions, such as impersonation or superadmin grants, in classic only. The server enforces each guard, and the client and MCP never offer what it refuses.
- **Masking and safe defaults.** `reactive { mask }` hides credentials. Binary, encrypted, and filtered columns are hidden by default, and large JSON values are summarized until a user expands them, which is audited.
- **Agent tokens.** Bearer tokens authenticate only under the API mount, never on classic routes, and scopes separate reads from writes.
- **Audit events.** reactiveadmin emits notifications for writes, exports, lookups, value reveals, refused requests, and MCP calls, with ids only and no record data.

### Developer experience

- **The doctor.** `rake reactiveadmin:doctor` samples every resource and page and reports what renders natively.
- **The legacy inventory.** `rake reactiveadmin:legacy` lists everything that still relies on classic ActiveAdmin, ranked by impact. A ratchet fails CI if the list grows.
- **The end-to-end crawl.** `pnpm crawl` visits every screen in the React client and checks for errors, failed requests, accessibility violations, and slow renders.
- **OpenAPI and docs.** The generated document is filtered to what the requesting admin may access. Hosts can render it with a viewer such as Scalar.

### Interface

- **Forms.** Forms get typed controls, typeaheads, date pickers with limits, native GET search forms, and compact editors for one-field nested rows.
- **Index pages.** Index pages get filter bars, scope tabs with counts, column sorting, and a command menu (⌘K) for navigation.
- **Accessibility.** Every Storybook story passes an axe check in light and dark themes.

## Limitations

The following limitations apply today. Track what still needs work in your app with the legacy inventory (`rake reactiveadmin:legacy`).

### Scope

- **ActiveAdmin 3.5.** The gem targets ActiveAdmin 3.5. An adapter for ActiveAdmin 4 exists as a stub, and CI probes it, but it isn't supported yet.
- **The `admin` namespace.** The client assumes the ActiveAdmin namespace is `admin` in its API paths.
- **Session-based hosting.** The default setup runs on the same origin as the host app. Cross-origin hosting needs the bearer adapter or a proxy.

### Views that stay classic

- **Custom JavaScript.** A template that depends on its own JavaScript renders as an embedded classic page until someone ports it to Formtastic forms or a custom React page.
- **Raw forms.** A template with raw HTML forms renders as sanitized HTML inline rather than as typed controls.
- **Print layouts and exports.** Print views and file exports open in classic, by design.

### Behavior differences

- **Inline styles.** The client ignores inline styles and layout classes it doesn't recognize. Content still renders, but spacing can differ from classic.
- **Host callbacks.** When the host serves the React shell instead of a classic page, the host's `after_action` callbacks don't run for that response. The API requests that follow are tracked as usual.
- **Date limits.** `min` and `max` on date inputs are enforced in the browser only. Your models still need to validate them.
- **Row-scoped options.** In repeated nested rows, typeahead searches beyond the inline limit use the first row's scope.

### Packaging

- **Distribution.** The gem installs from GitHub, not RubyGems, and the client isn't published as an npm package yet.
- **The contract file.** The OpenAPI builder reads `openapi/core.yaml` from the repository, so a packaged gem would need that file bundled.
- **Document size.** The OpenAPI document for an app with a hundred or more registrations is about 1 MB.

## Next steps

- To install and configure the gem, see [Getting started](getting-started.md).
- To learn the registration DSL, see [DSL reference](dsl.md).
- To review the security model, see [Security](security.md).
- To find out what ActiveAdmin features the API supports, see [ActiveAdmin support](activeadmin-support.md).
