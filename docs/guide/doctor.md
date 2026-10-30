# Doctor

`rake reactiveadmin:doctor` reports how much of your admin the typed API covers, and where it falls back to HTML or a frame. Use it to find the views that need work, and to stop coverage from slipping in CI.

## Run the report

From your app's root, run:

```sh
bundle exec rake reactiveadmin:doctor
```

The task loads the app environment, so run it where the database holds representative data. It always prevents writes, and it marks its requests as internal, so `background_request?` is true for them and hosts keep them out of their audit.

The doctor needs a user to sample records and pages as. Set one in the initializer:

```ruby
ReactiveAdmin.configure do |config|
  config.doctor_user = -> { AdminUser.find_by!(email: "ops@example.com") }
end
```

Without `doctor_user`, the doctor reads your code and nothing else. Its header then says `static: no sample user`, and the typed-versus-HTML counts come from declarations only.

### Pages that need params

A page that reads a required param, such as `Model.find(params[:extract_id])`, raises when the doctor renders it bare and is reported as `page_iframe_fallback`. Give the doctor params to render it with:

```ruby
config.doctor_page_params = lambda do |page_key|
  {extract_id: Extract.last&.id} if page_key == "extract_reviews"
end
```

The lambda gets the page key and returns a query hash, or `nil` to render the page without params as before. A page that still raises is reported as before.

## Options

Pass options as environment variables. They work with `rake` directly:

| Variable | Default | Effect |
| --- | --- | --- |
| `FORMAT` | text | `json` prints the whole report as JSON, including diagnostics. |
| `SAMPLE` | on | `0` skips requests and reads declarations only. |
| `BASELINE` | none | Path to a baseline YAML file. The task compares the run to it and reports regressions. |
| `WRITE_BASELINE` | none | Path to write a baseline YAML file from this run. |
| `THRESHOLD` | `0.5` | Allowed growth, in percentage points, for the two summary percentages before the run counts as a regression. |
| `MAX_FALLBACK` | none | A percentage. The run counts as a regression when the fallback share exceeds it. |

What each option does:

- **Sampling.** Without `SAMPLE=0`, the doctor runs the index with five rows, one record's show page, and the new form for each resource. It also renders each page. It runs these as the `doctor_user`, through the same callbacks and authorization as a real request.
- **Baseline.** `WRITE_BASELINE` records each action's mode, each page's mode, the summary percentages, and the failures.
- **Exit code.** The task exits `1` when the run finds any regressions, and `0` otherwise. A run with no `BASELINE` and no `MAX_FALLBACK` always exits `0`.

## Read the output

The text report has these parts. The numbers in these examples are illustrative, not from a real app.

**Summary.** Resource and page counts, filters built and skipped, and the number of actions by mode:

```text
reactiveadmin doctor
  resources 124, pages 19, filters 570/570 built (0 skipped)
  actions: api 150, native 4, frame 6, iframe 2, custom 0
  views (actions with a view + pages): native 9, frame 14, iframe 2, custom 0; fallback 33.1%
  typed vs html leaves: index 3167/3200, show 812/900, form 410/460; html 2.4%
  failures 0, diagnostics 3
```

**Fallback views.** Each action or page that doesn't render natively, with its mode and the reason the gem chose it:

```text
Fallback views
  authors#activation        frame   no Formtastic form
  authors#preview_schedule  iframe  needs the page's own JS (<script>)
  page coupons              frame   forms render as frame nodes
```

**Html leaves and skipped filters.** Resources that have HTML leaves in their index, show, or form sections, or filters that the gem skipped.

**API guards (accepted).** Every `api` declaration, with the resource or page, the guard, whether it covers everything or only named actions (`only`, `except`) or attributes, and its reason. These are decisions, not findings: a resource or page that is denied whole (`api false`), or whose every action a static `api :deny` covers, isn't sampled, and none count against coverage or appear in the legacy inventory, not even as `not_exposed`. The doctor samples as a session. A name in `only:` or `except:` that matches no action is an `api_guard_unknown_action` diagnostic, because it guards nothing.

**Menu links (accepted).** Every explicit `link "Label", url:` in `ReactiveAdmin.menu`, by its path in the menu, with its URL (`computed` for a proc). Like the guards, these are the host's decisions. Only menu nodes inherited from ActiveAdmin's own menu that point at a classic URL stay in the legacy inventory as `menu_link`. `FORMAT=json` has them under `menu_links`.

**Failures.** Sections that raised during sampling, with the exception class and the host file and line. Messages are never printed.

**Diagnostics.** Counts of problems the run recorded, such as menu mismatches, `exposure_permitted_not_exposed` (the resources and pages the doctor user may read that `config.expose = :listed` leaves out) and `exposure_unknown_key` (a key in `exposed_resources` that matches nothing), and `implicit_view` entries, which name the columns that secure defaults hide from a resource's index or show without a block. `FORMAT=json` shows each one, and each resource's `implicit_view` key.

A fallback is not a bug. A frame or iframe works for an operator. Use the reason to choose the next step. See [Custom views](custom-views.md#refactor-or-keep-the-frame).

## Set up the ratchet

A ratchet stops coverage from getting worse, and it lets you lock in each improvement.

1. Run the doctor once with your `doctor_user` set, and write the baseline:

   ```sh
   WRITE_BASELINE=config/reactiveadmin_coverage.yml bundle exec rake reactiveadmin:doctor
   ```

2. Commit the baseline file. It holds resource keys, action names, modes, and counts. It doesn't hold record data.

3. Add a CI step that compares each run to the baseline:

   ```sh
   BASELINE=config/reactiveadmin_coverage.yml MAX_FALLBACK=30 bundle exec rake reactiveadmin:doctor
   ```

4. When coverage improves, write the baseline again and commit the lower numbers.

### What counts as a regression

The comparison reports these problems. Each one adds to the exit count:

- **Mode downgrade.** An action or page that moves to a fallback further down the ladder. The order is `native` or `custom` or `api`, then `frame`, then `iframe`. Moving from `api` to `frame` counts. Moving from `frame` to `native` doesn't.
- **New failure.** A section that raised during sampling and didn't in the baseline.
- **Growth in a summary percentage.** `ladder_fallback_pct` or `html_node_pct` grew by more than `THRESHOLD`.
- **Above the cap.** `ladder_fallback_pct` is above `MAX_FALLBACK`.

Actions that are new since the baseline aren't compared. Add them by rewriting the baseline.

Review the diff when you rewrite a baseline to lower a number. Rewriting it to accept a regression hides the change from the next reviewer.

## Legacy inventory

`rake reactiveadmin:legacy` turns the doctor's findings into a checklist of everything that still relies on classic ActiveAdmin, so you can shrink it wave by wave. It uses the same sample user as the doctor.

```sh
bundle exec rake reactiveadmin:legacy
OUT=docs/legacy_inventory.md WRITE_BASELINE=config/reactiveadmin_legacy_baseline.yml bundle exec rake reactiveadmin:legacy
```

| Variable | Effect |
| --- | --- |
| `FORMAT` | `md` (default) prints the checklist. `json` prints the items and summary for CI. |
| `OUT` | Writes the report to a file and prints a one-line summary. |
| `BASELINE` | Path to a baseline YAML file. The task adds trends and a "Recently cleared" section, and exits `1` when new items appear. |
| `WRITE_BASELINE` | Path to write a baseline from this run. |
| `HTML_THRESHOLD` | Share of html leaves above which a view counts as html-heavy. Default `0.1`. |
| `SAMPLE` | `0` reads declarations only. |

Each item has a category, a resource or page key, the action, field or path, its mode and reason, an impact, a suggested fix, and a work package where one fits. Items name resources and structural paths. They never hold record values.

The impact depends on whether the item writes:

- **High.** A write action or form that renders in a frame, in an iframe, or only in classic. An action that answers `501`. A form that can't be submitted. A form field that shows as html.
- **Medium.** A read-only view in an iframe, a read-only classic link, a skipped filter, a classic menu link, a resource the policy permits but you haven't exposed, a nested resource with no entry point, or another degradation.
- **Low.** A read-only view in a frame, a host component, an html-heavy view, a capped typeahead scan, or a column that secure defaults hide (`implicit_*`).

Each item's category tells you what kind of finding it is:

| Category | Covers |
| --- | --- |
| `view_unsupported` | Views that answer `501`. |
| `view_frame`, `view_iframe`, `view_custom` | Views shown in a frame, in an iframe, or by a host component. |
| `action_unsupported` | Actions and links only the classic admin serves. |
| `form_not_submittable` | Forms the API can't submit. Every `form partial:` is listed here. |
| `degradation` | Fallbacks from sampled responses and diagnostics. |
| `html_heavy` | Sections where html is more than `HTML_THRESHOLD` of the leaves. |
| `filter_skipped` | Filters with no control the API can infer. |
| `typeahead_scan_capped` | Typeaheads whose scan hit its cap. |
| `menu_link` | Menu items that link to a classic URL. |
| `not_exposed` | Resources and pages the policy permits but `expose = :listed` leaves out. |
| `nested_no_entry` | Nested resources whose parent has no show page to link from. |

The checklist groups items by impact, then by resource. A summary table gives the counts per category and the trend against the baseline: `▲` more, `▼` fewer, `=` same.

### Work through it

1. Regenerate the checklist at the start of each wave and commit it.
2. Fix items, starting with high impact. The fix column says what to change, for example `convert the template to semantic_form_for`.
3. Regenerate. Fixed items move to "Recently cleared" and the counts fall.
4. Write the baseline again and commit the smaller file.

The ratchet stops the list from growing. A run with `BASELINE` exits `1` when an item appears that the baseline lacks, and never when items disappear. Add it to CI next to the doctor's check:

```sh
BASELINE=config/reactiveadmin_legacy_baseline.yml bundle exec rake reactiveadmin:legacy
```

Review the diff when you rewrite the baseline. Rewriting it to accept a new item hides the item from the next reviewer.

## Layout classes and inline styles

The walker turns a safelisted set of utility classes into typed layout hints, and never passes raw classes or styles to the client. Anything else is reported as `unknown_layout_class` or `inline_style_ignored`, in the doctor's diagnostics and `rake reactiveadmin:styles`. They are not degradations: the content renders and only some spacing is lost, so users see no notice.

| You write | The client gets |
| --- | --- |
| `flex`, `flex-col`, `gap-N`, `items-*`, `justify-*`, `lg:flex-row`, `grid-cols-N` | `layout` |
| `w-1/2`, `w-full`, `col-span-N`, `max-w-sm` to `max-w-2xl`, `grow` | `width`, `span`, `max_width`, `grow` |
| `mt-N`, `mb-N`, `ml-N`, `mr-N`, `mx-N`, `my-N`, `m-N`, with N from 1 to 8 (4px steps) | `spacing` |
| `text-left`, `text-center`, `text-right` | `text_align` |
| `font-bold`, `font-semibold`, `italic` | `marks` (`strong`, `em`) |
| `text-muted`, `text-success`, `text-danger`, `text-warning`, or `text-gray`, `red`, `green`, `yellow`, `orange`, `amber` with a shade | `tone` |
| `whitespace-nowrap`, `text-nowrap` | `nowrap` |

An inline `style:` reads as the same classes, one declaration at a time, and only when the value lands exactly on the vocabulary: `8px`, `1rem` and `0.5rem` are spacing steps, but `10px`, `1em`, `auto` and negative margins are not. A zero margin says nothing and is dropped. Classic needs CSS for any class you use, so prefer a class where your stylesheet defines it, and keep the inline style where classic's scale differs from the vocabulary's (a host's `gap-5` may not be 20px).

Each diagnostic carries the exact `class` or `style` string and, where it can be found, a `source` such as `app/admin/authors.rb:621`. A tag built by the DSL names its own line. Markup from ERB and helpers is found by scanning `app/` for the string, so it may name more than one line.

### Report on them

```sh
bundle exec rake reactiveadmin:styles                      # markdown
FORMAT=json OUT=tmp/styles.json bundle exec rake reactiveadmin:styles
SAMPLE=0 bundle exec rake reactiveadmin:styles             # source scan only, no records needed
```

The report has two parts. `Sampled` is what the API degrades on for the sampled records, grouped by resource with counts and sources. `Source scan` is every string in `app/admin` and `app/views/admin` that has no translation, whether or not a sample reached it, with what to use instead. The legacy inventory names the same strings in the reason of its `degradation` items.

## Troubleshoot

- **Every section shows `failures`.** Check that `doctor_user` is an active admin who may read the resource. A `403` or a `401` in a sample is recorded as a failure.
- **The run is slow.** Set `SAMPLE=0` for a quick declaration check, and sample in CI only.
- **A page shows as a failure with `render`.** The page's content raised while rendering as the sample user. Load the page in the browser as that user to see the error.
