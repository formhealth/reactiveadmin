# DSL

reactiveadmin reads your ActiveAdmin declarations as they are. Use the DSL only for hints the classic admin doesn't need. You can add four kinds of hints:

- A `reactive do ... end` block inside a resource, for search, masking, menu placement, exposure, exposed actions and render modes.
- `api` guards, for what the API must refuse.
- Named option sources, for typeahead inputs.
- A menu overlay, for placing resources and pages in the navigation.

## The `reactive` block

Add a `reactive` block inside an `ActiveAdmin.register` block or a `register_page` block:

```ruby
ActiveAdmin.register Author do
  reactive do
    search :family_name, :given_name, :email
    mask :ssn
    menu path: ["Editorial"], priority: 20
    expose :merge, if: ->(record) { record.active? }
    render_as :frame, action: :team_history
  end
end
```

The block accepts these methods.

### `search`

```ruby
search :family_name, :given_name, :email
```

Lists the columns that typeahead searches when this resource is the target of an association input. Only text columns count. Without this call, the gem searches the display-name methods, then common name columns such as `name` and `first_name`. Use `search` when those defaults don't match what operators type.

Pasting a record's id also finds that record, whichever columns you search.

### `mask`

```ruby
mask :ssn, :date_of_birth
```

Masks the named attributes in this resource's index, show, and form. The gem sends a `masked` node in place of each value, and it never sends the value in a form. Use `mask` for a secret on one resource. Use `config.masked_attributes` for a name that applies across the app. See [Security](security.md#masking).

### `sensitive`

```ruby
sensitive true
```

Marks this resource's display names as sensitive. Lookups that return its records (typeahead, `_options/lookup`, `_labels`) publish `lookup.reactiveadmin`. `sensitive false` opts out of `config.sensitive_resources`. See [Security](security.md#lookup-audit).

### `menu`

```ruby
menu path: ["Setup", "Billing"], priority: 30, label: "Invoices", icon: "receipt"
```

Places the resource in the menu without changing its AA `menu` call. The `path` lists group labels from the top. It can hold at most two labels. An empty array places the resource at the top level. The options `priority`, `label`, `description`, and `icon` are optional.

If you also declare a placement in `ReactiveAdmin.menu`, the overlay wins. See [Menu overlay](#menu-overlay).

### `new_needs_parent`

```ruby
belongs_to :author, optional: true
reactive { new_needs_parent }
```

For a resource with an optional `belongs_to` whose `new` can only build under its parent, for example `build_new_resource` calls `Author.find(params[:author_id])`. The manifest then leaves `new` and `create` out of the resource's `actions` and `permissions`, so the client offers no top-level New button and the crawl skips the form. Index, show and edit still work at the top level. The nested `new` route is unchanged.

### `nested_layout`

```ruby
reactive { nested_layout :admin_policy_permissions, :cards }
```

Sets how a `has_many` section lays out its rows: `:compact` or `:cards`. Without it, the gem picks `compact` when every row holds exactly one visible control (a text, select or single typeahead; the hidden `id` aside) and the section isn't `sortable`, and `cards` otherwise. A compact section is a dense list: one line per row, the section heading as the label (without `heading:`, the single control's label, pluralized: "Admin policy" becomes "Admin policies"), an add control at the bottom, and pending removals shown struck through with Undo. Saved rows read as plain text; selecting one turns it into its control, and Escape puts it back. The write is the same `*_attributes` either way. Add `max_rows: 10` to `has_many` to stop the client offering more rows; the server doesn't enforce it.

### `expose`

```ruby
expose :merge
expose :archive, if: ->(record) { record.active? }
```

Lists a member action, or a GET collection action, as a header button. Without `expose`, an action appears only when an action item or a link in the content references it.

The `if:` lambda receives the record for a member action. It receives no arguments for a collection action. The lambda runs in the view context, so helpers such as `current_active_admin_user` are available. If the lambda raises, the button stays hidden.

Non-GET collection actions can't be exposed. They're forms, and a button alone can't submit their params.

Pass `true` or `false` instead of an action name to set exposure for the whole resource or page:

```ruby
expose true   # serve it under config.expose = :listed, without a menu placement
expose false  # deny it, even when a menu or exposed_resources lists it
```

Both apply only when `config.expose = :listed`. See [Security](security.md#exposure).

### `render_as`

```ruby
render_as :frame, action: :team_history
render_as :custom, action: :board, custom_key: "team-board"
render_as :iframe
```

Forces how a custom view is shown. Modes are `native`, `frame`, `iframe`, and `custom`. The `custom` mode requires `custom_key:`. Without `action:`, the override applies to every custom action of the resource, or to the page content for a page. See [Custom views](custom-views.md) for what each mode means.

## `api`

```ruby
api false                                       # everything, the same as api :deny
api :deny, only: [:impersonate, :do_impersonate]
api :deny, except: [:index, :show]              # everything but these
api :deny, attributes: [:superadmin]            # writes that include these
api :read_only                                  # GET and HEAD only
api :session_only, only: [:destroy]             # the React client yes, API tokens no
api :superadmin_session, only: [:update], reason: "Superadmins edit from the admin"
```

Makes the server refuse what must not run through the API, whoever asks and however they authenticate: the React client and anything else that dispatches through it, such as MCP. The classic admin is unaffected. `api` is a top-level call in an `ActiveAdmin.register` or `register_page` block, like `menu`, not inside `reactive do`. Calling it inside `reactive do` also works.

```ruby
ActiveAdmin.register User do
  api :deny, only: [:impersonate, :do_impersonate], reason: "Impersonation happens in the classic admin"
  api :deny, attributes: [:superadmin]
end
```

The first argument is the guard:

| Guard | The API refuses |
| --- | --- |
| `false` or `:deny` | The named actions, or everything without `only:` and `except:`. |
| `:read_only` | Everything but GET and HEAD: writes, and member, collection, page and batch actions that aren't GETs. The forms of the writes it refuses (`new`, `edit`) go too, because they can't be submitted. |
| `:session_only` | Requests that authenticate with a token (a bearer header, as MCP does). A signed-in session, the React client, is let through. |
| a registered name | Whatever your guard says. See below. |

Options:

- **`only:` and `except:`** work like `before_action`, and don't combine. Names are member, collection and page actions, standard actions (`:index`, `:show`, `:new`, `:create`, `:edit`, `:update`, `:destroy`), `:batch_action` for all batch actions, or the name of one batch action. `:new` and `:create` go together, as do `:edit` and `:update`, in `only:` and in `except:`: a form you can't open is one you may not submit. Without either, the guard covers the whole resource or page: index, show, forms, exports, `_meta`, `_options`, `_value`, `_labels`, every write and every action.
- **`attributes:`** applies the guard to writes that include one of these names at any depth of their params, including inside `*_attributes`. Reading them is unchanged. For an association, the foreign key and `_ids` count too. It combines with `only:` and `except:`, which scope the write actions that check it (the default is every write). `:read_only` takes no attributes.
- **`reason:`** is the message users read instead of the guard's default.

Guards stack: any refusal wins. A refused request gets `403` with code `api_denied`, the `guard` that refused, a `classic_url`, and for attributes their names. See [Security](security.md#api-guards).

### What the metadata says

`deny`, `read_only` and `session_only` are static: the manifest, `_meta`, form payloads, the menu, the OpenAPI document and MCP already know what they refuse, so each channel is told what is true for it.

- A denied action or attribute is marked `api_denied: true` with a `classic_url`, and the client shows a link to the classic admin, opened in a new tab, instead of a button or an editable field. A resource or page denied whole leaves the manifest, and its menu entry becomes a link to the classic page.
- For a session, `:session_only` actions are offered as usual. For a bearer or MCP request they are marked like any denial. OpenAPI documents them for a session with `x-reactiveadmin-session-only: true`, and leaves them out for a token.
- MCP never lists a denied resource, page, action, batch action or field.
- A resource or page whose every action a static `:deny` covers, whether declared whole (`api false`) or action by action, is an accepted decision: the doctor lists it under "API guards (accepted)", and the legacy inventory never reports it as `not_exposed`.

### Custom guards

Register a guard once, in an initializer, and name it in `api`:

```ruby
ReactiveAdmin.api_guard(:superadmin_session) { |user, request| user.superadmin? && !request.authorization }
# the same:
ReactiveAdmin.api_guards[:superadmin_session] = ->(user, request) { user.superadmin? }
```

The block gets the current user and the request, and returns true to allow. It runs on every request the declaration covers, so the metadata can't know the answer: it stays, and carries `api_guard: "superadmin_session"` (`x-reactiveadmin-guard` in OpenAPI, and "may be refused (superadmin_session)" in MCP). A guard that returns false, raises or is no longer registered refuses; nothing here fails open. Registration has to happen before the admin files load: a name that isn't registered raises `ArgumentError` when the declaration is read, so a typo stops the boot.

`rake reactiveadmin:doctor` lists every declaration, and reports a name in `only:` or `except:` that matches no action as `api_guard_unknown_action`, because it guards nothing.

## Option sources

Use an option source when several inputs share one list, or when a list needs a search that the model can't express. Register sources once, in an initializer or another file that loads with the app:

```ruby
ReactiveAdmin.option_sources do
  source :authors, -> { Author.all }, label: :name, search: [:name, :email]
  source :posts, -> { Post.all }, label: :title, search: [:title]
end
```

Each `source` takes a name, a relation, and these options:

| Option | Default | Purpose |
| --- | --- | --- |
| `label` | The record's display label | A method name or a proc that returns the option label. |
| `value` | `:id` | A method name or proc that returns the submitted value. |
| `search` | Resolved from the model | The columns the typeahead searches. |
| `hint` | `nil` | Secondary text shown under each option. |
| `policy` | `scope_options_by_policy` | Whether to limit the list to rows the user may read. |

The relation can also be a lambda. The lambda runs in the view context, so it can read the current user. A plain array works too. Array entries are `[label, value]`, `[label, value, hint]`, or `{label:, value:, hint:}`; the hint is optional, searched with the label, and shown muted next to it. The classic admin ignores hints.

### Use a source in a filter or form

Pass `as: :typeahead` and `source:` to a filter or an input:

```ruby
filter :author_id_eq, label: "Author", as: :typeahead, source: :authors

form do |f|
  f.inputs do
    f.input :author, as: :typeahead, source: :authors
  end
end
```

The classic admin renders the same source as a datalist. The API renders it as a searchable typeahead. The API inlines the list when it has at most `inline_options_limit` entries. Larger lists load through the `_options` endpoint as the user types.

### Scope a source to a parent

Use `scope:` to narrow a source. A lambda with one argument receives the relation. A lambda with two arguments also receives the form object:

```ruby
f.input :post, as: :typeahead, source: :posts,
  scope: ->(posts, form) { posts.where(author_id: form.object.author_id) }
```

Inside a `has_many`, the form object is the parent record's form.

## Menu overlay

Use `ReactiveAdmin.menu` to place resources, pages, and links in one file. The overlay sits on top of ActiveAdmin's own menu:

```ruby
# app/admin/menu.rb
ReactiveAdmin.menu do
  group "Setup", priority: 90, icon: "settings" do
    group "Billing" do
      resources :billing_plans, :invoices
      page :batch_operations
      link "Sidekiq", url: "/sidekiq", if: -> { current_active_admin_user.superadmin? }
    end
  end
  hide :legacy_reports, :batch_operations
end
```

Keep the file under `app/admin` so it reloads with ActiveAdmin.

### Rules

- **Precedence.** The overlay wins over `reactive { menu path: }`, which wins over AA's `menu parent:`. Anything the overlay doesn't place keeps ActiveAdmin's placement.
- **Depth.** Use at most two levels of groups. Put items inside the second level. Deeper nesting raises `MenuOverlay::DepthError` in development and test. In production, it logs a warning and records a diagnostic.
- **Visibility.** Items the user may not see stay out of the menu. Groups left empty are removed.
- **Hidden in AA.** Placing a resource or page that AA hides with `menu false` shows it in the React menu. The classic AA menu doesn't change. The `comments` resource works the same way when `config.comments = false` (its key is `comments_registration_name` underscored and pluralized, such as `admin_comments`). Placement doesn't skip authorization: the user still needs read access. A resource without an `index` action, or one that exists only under a required `belongs_to` parent, can't be placed.
- **Links.** `link` takes `url:` as a string or a proc, and `if:` as a lambda. Both run in the view context, so helpers such as `authorized?` are available. A `link` is an explicit decision: the legacy inventory doesn't list it as a classic menu link, and the doctor lists it under "Menu links (accepted)". Only links the menu inherited from ActiveAdmin that point at classic URLs stay in the inventory.
- **Hiding.** `hide :key, ...` marks resources and pages as intentionally absent from the React menu. They are removed from the menu even where AA places them, and the audit no longer reports them as unplaced. It works at the top level and inside groups. Hiding doesn't make a resource exposed under `expose = :listed`.
- **Audit.** The overlay records mismatches as diagnostics when the menu builds. It flags duplicate placements, keys that don't match a registered resource or page (including keys passed to `hide`), placed keys that can't appear (`menu_hidden`: no `index` action, nested under a required parent, or denied under `expose = :listed`), and resources that the overlay doesn't place and doesn't `hide`.

## Limit the fields sent

Control the fields in the classic declarations, and use `mask` for values that must never leave the server:

- With an `index`, `show`, or `form` block, the API sends only the fields that block declares.
- Without a block, index and show summarize json columns, truncate text columns (both expandable through the audited `_value` endpoint), and omit binary, encrypted, filtered, and masked columns under the default `implicit_defaults = :secure`. The default form shows ActiveAdmin's default inputs.
- If a block raises, the gem logs a warning and falls back to the defaults. It doesn't stop the request.

For resources that hold sensitive data, declare an explicit block for each section. Read [Security](security.md) for the full guidance.
