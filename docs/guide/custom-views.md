# Custom views

ActiveAdmin lets you write any view, but the API can only type the forms and layouts it understands. A custom view that the API can't type still works. reactiveadmin picks the least-invasive way to show it, and that choice is the fallback ladder.

## The fallback ladder

The ladder has four modes, from best to last resort:

| Mode | What the client gets | Chosen when |
| --- | --- | --- |
| `native` | A typed `FormResponse`, rendered by the client's form renderer. Small forms open in a dialog. Larger forms open as a page. A read-only view gets a `PageResponse` of typed nodes, as a page. | The view has Formtastic forms and no raw form controls or custom builder calls. Several forms, tables, `button_to` and `link_to` with `method:` or `confirm` are fine. Or the view is read-only: no form, no raw controls, no `button_to` or `link_to` with `method:` or `confirm`, and no script. |
| `frame` | The classic page without ActiveAdmin's layout, as HTML inside the app. The client sanitizes it before display. | The view has markup or controls the API can't type, such as raw form tags or `form_tag`. Also used when a view has no Formtastic form but does hold raw controls or actions. |
| `iframe` | The classic page in a same-origin iframe, with the chrome hidden and a small bridge script. | The page needs its own JavaScript, such as a `<script>` tag, a `data-controller` attribute, or a `remote: true` link. |
| `custom` | A host React component, registered under a key. | You set `render_as :custom` and register a component. |

The gem picks a mode from the view's source, so the decision costs nothing per request. It reads the template and every partial that it renders. Decisions are cached in production and recomputed on reload in development.

Pages (`register_page` content) follow a similar rule. Plain content walks into typed nodes. A `semantic_form_for` or `active_admin_form_for` form, in the content or in a partial it renders, becomes a native `form` node when the recorder can describe it faithfully: it posts, goes to a route of the admin (usually a `page_action`), and holds Formtastic inputs only. A GET form that goes to the page itself is native too (see [GET forms](#get-forms-filters-and-results)). A write to it gets the params a browser's post of the form would have, so a blank field arrives as `""` as it does in classic. A choice list over `inline_options_limit` is searched through the page (`?context=page_form`). Raw controls, GET forms that go to another page, and forms that post off-site or outside the admin still render as frames. Scripts render as an iframe. Show-page content gets the same form nodes, except that a long choice list keeps its form a frame.

### Rules for an action view

The gem checks these in order. The first match decides the mode:

1. Script-dependent markup, such as `<script>`, `<iframe>`, `javascript_include_tag`, `data-controller`, `remote: true`, inline `on*` handlers, or `javascript:` links. The result is `iframe`.
2. No `semantic_form_for` or `active_admin_form_for`. The result is `native` when the view is read-only (no raw controls and no `button_to` or `link_to` with `method:` or `confirm`), and `frame` otherwise.
3. Raw controls, such as `<form>`, `<input>`, `<select>`, `form_tag`, `form_with`, or `select_tag`. The result is `frame`.
4. Tags beyond a simple set: headings, `p`, `div`, `span`, `a`, `strong`, lists, `section`, and tables. The result is `frame`.
5. Builder calls beyond Formtastic's, such as `f.some_helper`. The result is `frame`.
6. Otherwise, `native`.

A read-only view is walked into the same typed nodes as a show page, with a leading heading as the page title. Stored markup in it never becomes an action. The source check can miss controls that a helper or a stored value renders. When the rendered html holds a form, input, button or a link that acts, the request answers `501` and the view is a frame until the next reload.

Native forms get the `dialog` presentation when they have six or fewer inputs and the view shows nothing else. A view with several forms, actions or tables gets the `page` presentation.

### Several forms, row actions and results

The first Formtastic form of the view is the `FormResponse`. When the view shows more than that, the response also has a `layout`: the view's content as typed nodes, in order, with a `form` node that has no payload standing for the response's own form. A view gets a layout when it has:

- Further forms. Each is recorded like a page form and becomes an inline `form` node with its own `FormResponse`. A form the recorder can't describe, or one with a choice list over the inline limit, stays a `frame` node.
- Controls that act. A `button_to` form or a `link_to` with `method:` or `data-confirm` becomes an `action` node, mapped to the API like the actions on a show page. A route the API doesn't serve becomes a disabled action that links to the classic admin.
- Content after the form, such as the results of a search.

A heading above the form is the title. Without a layout, content around the form stays in `form.sections` as html fields.

A `button_to`, `form_tag` or `link_to ... method: :post` that goes to a route of this host outside the admin (an OmniAuth start such as `/auth/provider`) becomes a navigating action (see [Navigating POST buttons](#navigating-post-buttons)).

A write that renders its template again instead of redirecting (a search that lists matches) answers `200` with a new `FormResponse`, which the client shows in place of the form. It answers `422` when the write was rejected: an alert flash, or errors on the record or on the object the form was built from.

## GET forms: filters and results

A `semantic_form_for` or `active_admin_form_for` with `method: :get` is native when it goes to the view that renders it: a member or collection action template, or a `register_page`'s content. The form's `action` is `{method: "get", path}` with the API path of the same view. Submitting it is a navigation, not a write:

1. The client serializes the fields into a query string with Rails param names (`simulation[date]=2026-10-01`; lists as `tags[]`; blanks stay blank, as a browser sends them).
2. It fetches the same view in API format with that query, and shows the results layout (tables and panels after the form) in place.
3. It puts the same query in the browser URL, so back, forward, bookmarks and deep links work. A page loaded with a query renders its results at once, and the fields come prefilled from the response, which Formtastic fills from the object the action built from `params`.

The request is a GET of the action like any other. It passes the same authentication, read authorization, rate limit and `api` guards, and never a CSRF check, a write audit or a write guard. A choice list over `inline_options_limit` is searched through the same view (`?context=template` for a template, `?context=page_form` for a page). The search carries the query the view was loaded with, minus the endpoint's own params (`context`, `form`, `field`, `term`, `value`, `limit`, `cursor`), so a choice list whose scope depends on a param finds its options.

A template whose only forms are GET Formtastic forms, with markup the walker already accepts, is `native`, shown as a page. A GET form to another page, or in a show page's content, stays a frame, and a template with one answers `501 unsupported`.

```erb
<%# app/views/admin/users/preview_schedule.html.erb, for `member_action :preview_schedule, method: :get` %>
<h2>Preview schedule</h2>
<%= semantic_form_for @simulation, as: :simulation, url: preview_schedule_admin_user_path(resource), method: :get do |f| %>
  <%= f.inputs do %>
    <%= f.input :date, as: :date_picker %>
    <%= f.input :channel, as: :select, collection: Channel.pluck(:name, :slug) %>
  <% end %>
  <%= f.submit "Simulate" %>
<% end %>

<% if @simulation.run? %>
  <table>...</table>
<% end %>
```

The action builds `@simulation` from `params[:simulation]`, so classic prefills from it and so does the API. Name the form's object with `as:` so the params read `simulation[date]`. In a page, use the same form inside `content`, with `url: admin_my_page_path`. A query of `q[...]` is a ransack search to the API's guard: declare `reactive { own_query_params :preview_schedule }` or use another key.

The client's `submit` sends only the declared fields, and does not send the submit button's own `commit` param. A template that branches on `params[:commit]` should branch on its fields instead.

## Navigating POST buttons

A button that must make the browser POST to a route outside the admin and the API mount, such as an OmniAuth start, can't run through the API: the target answers with a redirect to another site. A `button_to`, `link_to ... method: :post`, or a `form_tag` (or an Arbre `form`) that holds only hidden fields and one submit button, rendered by the DSL, becomes an action with `kind: "link"`, `method: "post"` and `navigate: true`. Its `href` is the absolute URL, and `params` holds the form's hidden fields. The client submits a real hidden `<form method=post>` in the top window with the session's CSRF token as `authenticity_token` (a full navigation, not a fetch and not a popup), after the action's confirm if it has one.

```ruby
content do
  para { button_to "Connect with Provider", "/auth/provider", params: {origin: admin_connections_path} }
end
```

The rules:

- Only a POST, only this host and origin, over http(s), at a path outside the admin namespace and the API mount, with no dot segments, encoded slashes or userinfo. A foreign host stays an external link that opens as a GET. Everything else the walker can't route stays a disabled link to the classic admin.
- Only what the DSL rendered. A form or link in a stored value, or literal `<form>` markup in ERB, has no provenance stamp and never becomes an action (see [Security](security.md#typed-nodes-and-where-markup-comes-from)).
- Only for a session. A bearer token (MCP, scripts) gets no node and no action: it has no browser and no cookie to carry. MCP tools never expose it.
- It never goes through the API, so `api` guards don't apply to it, and they don't turn it into a classic link. A page the guards deny isn't served at all.
- The target must accept the session's CSRF token (for OmniAuth, `omniauth-rails_csrf_protection`) and, in development, be proxied to the Rails host.

## Form partials

A `form partial:` in a resource's form renders as a custom template does. Its Formtastic inputs are recorded as typed fields, and the rest of the partial stays as html around them. The form is submittable, so Save works, unless the partial holds raw inputs or fails to render. In those cases the response sets `submittable: false`. See [Security](security.md#forms-that-cant-be-submitted).

## Content in a form

A `form do |f|` block can print more than inputs: a heading with the record's name, an `attributes_table_for` of the current plan, a notice, a `panel` around `f.inputs`. The server walks that content into typed nodes with the same walker as a show page, and sends each run of it as a `content` field in the section where it appeared:

```ruby
form do |f|
  h3 { strong { f.object.author.display_name } }
  panel "Current plan" do
    attributes_table_for current_plan { row :name }
  end
  panel "New plan" do
    inputs { input :billing_plan_id, as: :select, collection: plans }
  end
end
```

The field has `control: content`, no `param` and no `value`, and its `layout` holds the nodes. It is read-only and never part of a write. A panel that holds inputs keeps its title as a heading above them, and its wrappers are copied around each run of content they span. The same rules apply as on a show page:

- A `link_to`, `button_to` or `form` the block builds becomes an action. Stored text printed with `raw` never does.
- Masked attributes in `attributes_table_for` rows show as masked.
- Forms inside content don't become frames, and markup the walker can't type falls back to sanitized html, which the doctor counts as html.

The doctor counts the typed content as typed. A form is html-heavy only for content it can't type, and for inputs that have no control.

## How writes work in each mode

A write goes through ActiveAdmin's own controller, so validations, callbacks, `controller do` overrides, and flashes behave as they do in the classic admin. Only the transport changes.

### Native

The client posts JSON or multipart form data to the API path, with the `X-CSRF-Token` header:

- A redirect returns `200`, or `201` for `create`, with `{"ok": true, "id": "...", "message": "...", "location": {...}}`.
- A failed validation re-renders the form. The response is `422` with code `invalid`, field errors under `errors`, and the form payload under `form`, so the client can redraw the fields with their messages.

### Frame

The client fetches the classic URL with the `X-Reactiveadmin-Frame: 1` header:

- Form submits go to the classic URL. The client moves the CSRF field into the `X-CSRF-Token` header and keeps `_method` and the submit button in the body.
- A redirect returns `200` JSON with `{"redirect": {...}, "flash": {...}}`. The client navigates to the redirect and shows the flash as a toast.
- A failed validation re-renders the HTML, which replaces the frame's content.
- An attachment response, such as a CSV or a PDF, downloads.
- A bad CSRF token returns `422` with code `invalid_csrf`.

### Iframe

The client loads the classic page with `?embed=1`. The page submits as a normal browser form:

- The bridge adds `embed=1` to each form's action, so the redirect stays inside the embed.
- A redirect keeps `embed=1` on the new URL.
- The bridge reports the result to the parent window with `reactiveadmin:navigate` and `reactiveadmin:flash`.

### Custom

The host component calls the API itself, through the generated client. The gem does nothing extra for writes in this mode.

## Force a mode

Use `render_as` in the `reactive` block to override the decision:

```ruby
ActiveAdmin.register Author do
  reactive do
    render_as :frame, action: :team_history
    render_as :custom, action: :board, custom_key: "team-board"
  end
end
```

Without `action:`, the override applies to every custom action on the resource. For a page, it applies to the content. See [DSL](dsl.md#render_as).

Use an override when the decision is wrong for a view you control. A forced `native` on a view the gem can't type returns `501 unsupported` on a GET, so run `doctor` after you change an override.

## Register a custom component

Register a React component under the same key you pass to `custom_key:`. The component receives `resource`, `id`, `action`, and an optional `onClose`:

```ts
import { registerCustomPage } from '@/views/customPages'

registerCustomPage('team-board', ({ id, onClose }) => (
  <TeamBoard authorId={id} onDone={onClose} />
))
```

Without a registered component, the client opens the classic page in a frame.

## Embed bridge messages

The bridge runs only when the page is inside an iframe, and it posts only to the same origin. Listen for these messages in the parent:

| Type | Payload | Sent when |
| --- | --- | --- |
| `reactiveadmin:resize` | `{ height }` | The page loads, the page resizes, and after the window's load event. `height` is the height of `body`. |
| `reactiveadmin:navigate` | `{ url, redirected? }` | The operator clicks a same-origin link to another admin page, or a redirect lands. The `url` has `embed` removed. |
| `reactiveadmin:flash` | `{ flashes: [{ type, message }] }` | The page renders flash messages. |

The bridge doesn't handle links that act, such as `data-method`, `data-remote`, `data-confirm`, links that open a new tab, and downloads. Those stay in the iframe and rails-ujs handles them.

Check `event.origin` in the parent before you act on a message.

Report the height of `body`, not `documentElement`. Otherwise the iframe can't shrink.

## Refactor or keep the frame

Frames are a working answer. Refactor a view when the cost of the frame is higher than the cost of the change.

Refactor to `semantic_form_for` (or `active_admin_form_for`) when:

- The view is one form that submits to a write action.
- Operators use the form often enough to benefit from typed fields, inline validation, and keyboard entry.
- The form fits Formtastic's inputs and the `actions` block.

Keep it as a frame when:

- The view is mostly display, or operators use it rarely.
- The markup is custom and a rewrite would lose layout that matters.
- The view has raw controls (`form_tag`, `form_with`, `<input>`) that Formtastic can't express.

Keep it as an iframe when the page needs its own JavaScript, such as a date-range widget or a tom-select control. Refactor only if the script can be removed or replaced by a Formtastic input.

Track the decisions with [`rake reactiveadmin:doctor`](doctor.md). It lists each fallback view with its mode and the reason for it. Use it to decide which views are worth the effort.
