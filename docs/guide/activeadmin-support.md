# ActiveAdmin support

This page lists which ActiveAdmin constructs the API and client handle. Use it to decide whether a resource is ready, or which parts still need the classic admin.

## Status

- **Supported.** The construct works and returns typed output.
- **Degraded.** The construct renders, but it loses behavior. The gem logs a warning or uses a fallback.
- **In progress.** Code exists, but coverage is partial.
- **Not supported.** The construct is ignored, or the request returns an error.

Entries marked **(check)** rest on code reading or on the 2026-10-16 review. Verify them against your app before you rely on them.

Index, show, form and page responses list what they fell back to in a `degraded` array of `{kind, where, reason}`. `where` is a structural path such as `index/column[title]` or `form/section[1]`, and `reason` names the exception class, never its message or any record data. Each entry also publishes an `ActiveSupport::Notifications` event, `degraded.reactiveadmin`, with `resource`, `action`, `kind` and `where`, and the response carries `X-Reactiveadmin-Degraded: <count>`. A cell that fails renders as an `error` node, not `empty`. For fixes in your admin code, run [`rake reactiveadmin:doctor`](doctor.md).

## Index

| Construct | Status | Notes |
| --- | --- | --- |
| `index` table with symbol and block columns | Supported | Symbol columns send typed values. Block columns render typed nodes, with HTML only where no node type fits. |
| Column `sortable` and `sort_key` | Supported (check) | The review found a 500 when sorting a block column whose symbol is a database column. The code now sorts on a copy of the column. Verify on your resources. |
| `selectable_column`, `id_column`, `index_column` | Supported | The client derives row selection from batch actions. |
| Cell block raises | Degraded | The cell renders as an `error` node and the response lists a `cell_failed` entry. The gem logs a warning. |
| Index block raises | Degraded | Falls back to the default columns. The gem logs a warning. |
| `index as: :grid`, `:blog`, `:block`, or custom | Not supported | Ignored. The default table renders with no signal. |
| Multiple index views (`?as=`) | Not supported | Only the default view is available. |
| `actions do \|r\| item ... end` row items | Supported (check) | Rendered as row controls. |
| `per_page` array | Supported | The client offers the declared options. |
| `max_per_page` | Supported | ActiveAdmin doesn't cap `per_page`. The API clamps it to the lower of the resource's `max_per_page` and `ReactiveAdmin.config.max_per_page` (default 100), unless the resource offers larger sizes in `per_page`. |
| `pagination_total: false` | Supported | Total counts are `null`. A one-row probe finds the next page. |
| `scope_count: false` | Supported | Scope counts are omitted. |
| Scope counts (`show_count`) | Supported | Counts come back with the index response, one query per scope. |
| Scope `group:` | Not supported | Scopes appear as one flat list. |
| Scope `if:` | Supported (check) | Evaluated per request. |
| `download_links` and `csv do` | Supported | `GET /api/admin/<resource>.csv` streams ActiveAdmin's CSV. The client's export UI: check. |
| Filters: string, numeric, date range, boolean, select | Supported | Typed controls in the manifest. |
| Filters: `as: :datalist` or `:typeahead` with `source:` | Supported | Searchable typeahead through `_options`. |
| Filters: `check_boxes` with `multiple` | Degraded (check) | Sends an `_in` param. Check that the client renders multiple selection. |
| Filter `if:` and `unless:` | Supported (check) | Evaluated per request. |
| Filter options that depend on other values | Supported (check) | `_options` evaluates the collection with the request's view context. |
| Filters disabled with `filters = false` | Supported | No filter controls are sent. |
| Undeclared `q[...]` predicates | Supported | Rejected with `400` and code `invalid`. The API honors declared filters only. |
| Custom ransackers | Supported | Used for type inference. |
| "Current filters" sidebar | Replaced | The client shows active filters as removable chips. |

## Forms and writes

| Construct | Status | Notes |
| --- | --- | --- |
| `form do \|f\|` inputs, `has_many`, and errors | Supported | Field errors return in a `422` with code `invalid`. |
| `has_many` rows with a single control | Supported | Shown as a compact list instead of cards. Override per association with [`nested_layout`](dsl.md#nested_layout). A failed write names the row that failed in `row_errors`. |
| `semantic_fields_for` and `fields_for` with `index:` | Supported | Each row of a repeated group posts under the name Rails gives it (`parent[rows][0][email]`), so an API write carries the same params as the classic form. `child_index:` applies to nested-attributes associations only, as in Rails. |
| Date and datetime `input_html: {min:, max:}` and `datepicker_options: {min_date:, max_date:}` | Supported | The client disables days outside the range and flags a typed value outside it. A date, time, ISO string, number of days, or relative string such as `+1m` works. The server doesn't validate: do that in the model. |
| Content in a `form do \|f\|` block: headings, panels, `attributes_table_for`, paragraphs | Supported | Walked into typed nodes, as on a show page, and sent as `content` fields between the inputs. See [Content in a form](custom-views.md#content-in-a-form). |
| `as: :typeahead` or `:datalist` in forms | Supported | Uses `source:` and `_options`. |
| Custom Formtastic inputs in `app/admin/inputs` | Degraded | Sent as a read-only HTML field. |
| `form partial:` | Supported (check) | Formtastic inputs in the partial are typed fields. Other markup stays html. Raw inputs make the form non-submittable. See [Custom views](custom-views.md#form-partials). |
| Form block raises | Degraded | Falls back to the default form. The gem logs a warning. |
| `render :new` or `:edit` after a failed write | Supported | Returns `422` with field errors, keyed by the name of the field that posts each attribute. A custom `create` can render `new` with its record in `@resource`. |
| `def new` or `def edit` that calls `super { ... }` | Supported | The block runs before the form is described, so values it sets on `resource` are the form's defaults. A block that takes the format argument is skipped. |
| Blank values | Same as classic | The server posts a null text-like or select field as `""`, as a browser would, and drops an unselected radio. Booleans, files and lists keep their types. |
| `json` fields | Same as classic | Posted as JSON text, so `permit_params :attr` takes it and your code parses it. A host that permits `attr: {}` gets the structure instead. A null posts `""`. |

## Show pages

| Construct | Status | Notes |
| --- | --- | --- |
| Attributes tables, panels, and tables | Supported | Typed `attributes_table`, `panel`, and `table` nodes. |
| `tabs` and `columns` | Supported (check) | Typed `tabs` and `columns` nodes. |
| Layout classes, such as `flex`, `lg:flex-row`, `w-2/3`, `mt-4`, `font-bold`, and `text-muted` | Supported | A safelisted subset maps to typed hints (layout, width, spacing, text alignment, marks, tone). Other classes are ignored and reported. See [Layout classes and inline styles](doctor.md#layout-classes-and-inline-styles). |
| Inline `style:` | Partly supported | Declarations that land exactly on the same vocabulary translate (`margin-top: 8px`, `text-align: center`, `display: flex; gap: 20px`). The rest are ignored and reported. |
| `panel header_action:` | Not supported | |
| `button_to`, `link_to` with `data-method` or `data-confirm` | Supported (check) | Converted to typed actions. Confirmation text is kept. A POST to a route of this host outside the admin navigates the browser (see [Custom views](custom-views.md#navigating-post-buttons)). |
| `paginated_collection` | Not supported (check) | Page links may drop the query string. |
| `table_for sortable:` | Degraded (check) | Sort links stay in the classic markup. |
| `status_tag`, `auto_link`, and links to resources | Supported | Typed `status` and `ref` nodes. |

## Actions

| Construct | Status | Notes |
| --- | --- | --- |
| `action_item` | Supported (check) | Rendered as header actions. Guards are honored. |
| `clear_action_items!` | Supported | |
| `expose` in `reactive do` | Supported | Lists a member or GET collection action as a header button. |
| Member action with POST, PUT, PATCH, or DELETE and `redirect_to` | Supported | Returns `{ok, id, message, location}`, or `422` with errors. |
| Member action with GET that renders a template | Degraded | Served through the ladder as native, frame, or iframe. Returns `501 unsupported` when no mode fits (check). |
| Member GET that changes data and redirects | Degraded (check) | Avoid it. The client may run the action again when it follows the redirect. |
| `send_data` and `send_file` | Degraded (check) | Frame mode downloads attachments. Check the native path. |
| `render json:` in an action | Supported | Passed through as the response body. |
| `respond_to` and custom responders | Degraded | Writes run as HTML and are translated to JSON. A GET without a `reactiveadmin` branch returns `501 unsupported`. |
| `redirect_back` and referer redirects | Degraded (check) | The referer is a client path, not always a route the API knows. |
| `collection_action` | Supported (check) | A GET collection action can be exposed. A write action needs a form. |
| `controller do` overrides | Supported | The gem prepends its modules, so `super` reaches them. |
| Flash messages | Supported | `notice` becomes a toast. `alert` and `error` become errors. Other keys are dropped. |
| Nested resources with a required `belongs_to` | Supported | Routes under the parent. Top-level keys return `404`. |
| Optional `belongs_to` | Supported | Top-level and nested routes both work. |
| Decorators (`decorate_with`) | Supported (check) | ActiveAdmin applies decorations to the records. The gem has no dedicated spec for them. |

## Pages, menus, and chrome

| Construct | Status | Notes |
| --- | --- | --- |
| `register_page` content | Supported (check) | Served at `/api/admin/_pages/<key>`. Plain content is typed, and Formtastic forms become native `form` nodes. Raw forms fall back to frame, scripts to iframe. |
| Page actions | Supported (check) | |
| Page sidebars | Not supported | |
| Custom ERB templates | Degraded | Chosen by the ladder: native for Formtastic-only forms, otherwise frame, iframe, or custom. |
| Menu `parent`, `priority`, `if`, and `url` | Supported | AA's menu. |
| `ReactiveAdmin.menu` overlay | Supported | See [DSL](dsl.md#menu-overlay). |
| Utility navigation, site title, logout, and favicon | Supported | Served in the manifest's `site` object. |
| Breadcrumbs | Supported (check) | Built by the client. |
| `display_name` and `display_name_methods` | Supported | |
| Active Admin comments | Not supported | The gem doesn't hide a registered `comments` resource (check). |
| Impersonation banner | Not supported | |
| ActiveAdmin JavaScript | Supported | Datepickers, has_many add and remove, dropdowns, and confirmations are rebuilt in the client. Frame mode doesn't run classic JavaScript. Iframe mode does. |
| Localization | Degraded | Dates follow `localize_format`. Client UI strings are English only (check). |
| Authentication and CSRF | Supported | See [Security](security.md). |
| Pundit adapter and per-row permissions | Supported | Each row carries its own `permissions`. |
| `authorize_custom_actions` | Supported | See [Configuration](configuration.md). |
