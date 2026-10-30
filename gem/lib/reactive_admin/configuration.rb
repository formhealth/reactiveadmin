module ReactiveAdmin
  class Configuration
    # `info`: OpenAPI info overrides (default title "Admin API", the gem's version). `output`: where
    # `rake reactiveadmin:openapi` writes. `security_schemes`: name => OpenAPI scheme, replacing the
    # session cookie and CSRF token defaults (e.g. a bearer scheme).
    OpenApiSettings = Struct.new(:info, :output, :security_schemes)
    # The MCP endpoint (`{mount}/_mcp`) and the token scopes the API enforces; see ReactiveAdmin::Mcp.
    class Mcp
      # false, true, or ->(user) { boolean } so a host can gate the endpoint per user (feature flags).
      # Disabled answers 404.
      attr_accessor :enabled
      # Scopes a token needs for reads (GET) and writes. They apply only to tokens whose bearer block
      # returned `scopes:`; set one to nil to stop requiring it.
      attr_accessor :read_scope, :write_scope
      # Protected resource metadata URL (RFC 9728) sent in `WWW-Authenticate` on 401, so MCP clients can
      # find the authorization server.
      attr_accessor :resource_metadata_url
      # Browser origins besides this site's own allowed to call `_mcp`; requests without Origin are
      # not browsers and pass.
      attr_accessor :allowed_origins
      # Cap on one tool result, in bytes of JSON, and on `per_page` for list_records.
      attr_accessor :max_response_bytes, :max_per_page
      # Shown to the agent by `initialize`.
      attr_accessor :instructions

      def initialize
        @enabled = false
        @read_scope = "admin:read"
        @write_scope = "admin:write"
        @allowed_origins = []
        @max_response_bytes = 20_000
        @max_per_page = 25
      end

      def enabled_for?(user) = enabled.respond_to?(:call) ? !!enabled.call(user) : !!enabled

      def possibly_enabled? = enabled.respond_to?(:call) || !!enabled
    end

    # Serves the React client at the classic admin's URLs; see ReactiveAdmin::Ui.
    class Ui
      NOBODY = ->(_user) { false }

      # Whether the middleware answers browsers that chose the new admin (cookie) with the client's page.
      attr_accessor :enabled
      # ->(user) { boolean }: who may use the new admin and switch between the two. The client reads it from
      # `_session`; it is a UI gate, and the API authorizes the same as ever. Nobody by default.
      attr_accessor :available
      # :classic or :new, or ->(user) { mode }: the UI to start an available user in, until they choose.
      attr_accessor :default
      # Directory of the built client (`rake reactiveadmin:client:build`); a Pathname, String or callable.
      # Default: public/reactiveadmin in the host.
      attr_accessor :client_assets
      # URL prefix the built client is served under. A path (the gem serves it when nothing else does) or
      # an absolute URL (a CDN, which must be built with the same prefix).
      attr_accessor :asset_prefix

      def initialize
        @enabled = true
        @available = NOBODY
        @default = :classic
        @client_assets = nil
        @asset_prefix = "/reactiveadmin"
      end
    end

    attr_accessor :namespace, :mount_path, :inline_options_limit, :current_user,
      :meta_cache_key, :meta_cache_version, :meta_cache_ttl, :options_cache_ttl, :scope_options_by_policy,
      :after_authorize, :on_background_request, :doctor_user, :doctor_page_params, :masked_attributes, :mask_filter_parameters, :mask_csv, :html_trusted_hosts,
      :require_lock, :retryable_errors, :error_reporter,
      :inline_json_limit, :inline_text_limit, :value_token, :value_token_ttl, :strict_defaults, :exposed_resources, :max_per_page, :max_export_rows, :rate_limits, :sensitive_resources,
      :ransack_unguarded_actions, :auth
    attr_reader :authorize_custom_actions, :implicit_defaults, :expose, :openapi, :mcp, :api_guards, :ui

    def initialize
      @namespace = :admin
      @mount_path = "/api"
      @inline_options_limit = 100
      # ->(controller) { user }; falls back to the namespace's current_user_method.
      @current_user = nil
      # ->(user) { JSON-able }: what in the user changes the _meta payload (permissions, roles).
      # Users with an equal key share a cached payload.
      @meta_cache_key = ->(user) { user.try(:id) }
      # -> { value }: must change whenever admin code does, so a deploy never serves stale metadata.
      @meta_cache_version = nil
      @meta_cache_ttl = 5.minutes
      # Seconds a non-relation options list (literal arrays, computed collections) is kept; 0 disables.
      @options_cache_ttl = 60
      # Limit typeahead options to what the user may read (the target model's AA authorization scope).
      @scope_options_by_policy = true
      # true: every custom member/collection action (and batch_action) is authorized up front
      # through the adapter. :match_active_admin: only what AA itself authorizes, i.e. when the
      # action body loads `resource`/`collection`.
      @authorize_custom_actions = true
      # ->(controller) { ... } run after the manifest is authorized; a hook for hosts whose base
      # controller has authorization-verifying callbacks (e.g. `skip_authorization` under Pundit).
      @after_authorize = nil
      # ->(controller) { ... } run for requests the client marks as background (prefetch, _meta,
      # _options, _session): the host's place to skip view audits or session extension.
      @on_background_request = nil
      # -> { current user } what the namespace's current_user_method returns, for `rake reactiveadmin:doctor` to
      # sample pages and records as; without one it only reads code.
      @doctor_user = nil
      # ->(page_key) { {param: value} or nil }: query params the doctor renders a page with, for pages
      # that read required params (`Model.find(params[:id])`). nil renders without any.
      @doctor_page_params = nil
      # Attribute names (symbols or regexps) whose values are masked everywhere in the API, on top of
      # a resource's `reactive { mask ... }`; see Masking.
      @masked_attributes = []
      # Also mask attributes matching Rails' `filter_parameters`. Turn off where that list holds
      # fields operators legitimately see (names, emails) and name the secrets in masked_attributes.
      @mask_filter_parameters = true
      # Mask the same attributes in CSV exports, classic and API alike.
      @mask_csv = true
      # Updates must carry the `lock` token the edit form handed out; false accepts those without one
      # (clients that predate locking), still rejecting a stale token.
      @require_lock = true
      # Error classes (or their names, for constants that reload) answered 409 `retry` (with Retry-After)
      # instead of 500: concurrency guards the host raises when a write loses a race.
      @retryable_errors = []
      # ->(error, context) { ... } where unexpected errors are reported. `error` is a ScrubbedError (class,
      # backtrace and request only, never the original message), so it is safe to hand to any service.
      @error_reporter = ->(error, context) { Rails.error.report(error, context:, handled: true, source: "reactiveadmin") }
      # Hosts (an array, or a callable returning one) whose images and embedded documents html nodes may
      # load besides this site, e.g. a document CDN. Everything else external becomes a link.
      @html_trusted_hosts = []
      # Largest json value (bytes of JSON) a show page sends inline; anything bigger, and every index
      # cell, is summarized and fetched on demand from the audited `_value` endpoint.
      @inline_json_limit = 2048
      # The same for text columns a resource shows by default (see `implicit_defaults`): up to this many bytes
      # inline on show, anything longer, and every index cell, is truncated with an audited `expand_path`.
      @inline_text_limit = 2048
      # `_value` answers only for an `expand_path` this server signed for the same user, record and
      # field, so it never re-renders a page to learn what the field may expose. false: the legacy allowlist.
      @value_token = true
      @value_token_ttl = 15.minutes
      # Columns a resource without an `index`/`show` block shows. :secure shows json and text columns
      # summarized or truncated (the full value is an audited `_value` call) and leaves out binary
      # columns, encrypted, filtered and masked attributes; :all is AA's behavior.
      @implicit_defaults = :secure
      # true: a resource without an `index`/`show` block gets no columns or layout at all.
      @strict_defaults = false
      # :all serves every resource and page the policy permits. :listed serves only what the host
      # names (menu overlay, exposed_resources, `reactive { expose true }`); see Exposure.
      @expose = :all
      # Route keys (resources) and page keys served under :listed, for nested-only and hidden ones.
      @exposed_resources = []
      # Largest page the API serves, whatever `per_page` asks for. A resource's own `max_per_page`
      # still applies, and the page sizes it declares (`config.per_page = [25, 250]`) raise this for it.
      @max_per_page = 100
      # An export of more rows is refused (422); nil disables the limit.
      @max_export_rows = 10_000
      # Requests per user in a window, by endpoint: [count, period]. A bucket set to nil is unlimited;
      # `default` covers every other API request. false turns limiting off. Needs a shared
      # Rails.cache; a null store leaves requests unlimited.
      # Route keys of resources whose display names are sensitive (authors). Typeahead searches, option lookups
      # and `_labels` that return their records emit `lookup.reactiveadmin` (never the term or the names),
      # though they stay background requests. `reactive { sensitive true }` marks a resource from its own file.
      @sensitive_resources = []
      # Actions by resource route key whose `q` param is their own search form, not a ransack filter:
      # `{categories: [:search_by_tag]}`. The same as `reactive { own_query_params }`.
      @ransack_unguarded_actions = {}
      @openapi = OpenApiSettings.new({}, "openapi/admin.yaml", nil)
      @rate_limits = {options: [30, 10.seconds], lookup: [120, 1.minute], export: [5, 1.minute], value: [60, 1.minute], mcp: [120, 1.minute], default: nil}
      # How API requests authenticate: nil is the session (AA's `authentication_method`, CSRF on writes).
      # `ReactiveAdmin::Auth::Bearer.new { |token, request| user }` is for tokens, and
      # `ReactiveAdmin::Auth.any(session, bearer)` accepts both; see Auth.
      @auth = nil
      # Name => ->(user, request) { boolean }: the guards `api :name` in a registration runs on every
      # API request it covers; false (or an error) refuses. See ApiGuards.
      @api_guards = {}
      @mcp = Mcp.new
      @ui = Ui.new
    end

    def expose=(mode)
      raise ArgumentError, "expose must be :all or :listed" unless %i[all listed].include?(mode)

      @expose = mode
    end

    def implicit_defaults=(mode)
      raise ArgumentError, "implicit_defaults must be :secure or :all" unless %i[secure all].include?(mode)

      @implicit_defaults = mode
    end

    def authorize_custom_actions=(mode)
      raise ArgumentError, "authorize_custom_actions must be true or :match_active_admin" unless [true, :match_active_admin].include?(mode)

      @authorize_custom_actions = mode
    end

    def authorize_custom_actions? = authorize_custom_actions == true
  end
end
