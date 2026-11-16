require "nokogiri"
require "reactive_admin/version"
require "reactive_admin/configuration"
require "reactive_admin/aa"

module ReactiveAdmin
  autoload :Registry, "reactive_admin/registry"
  autoload :Paths, "reactive_admin/paths"
  autoload :Values, "reactive_admin/values"
  autoload :ValuePayload, "reactive_admin/value_payload"
  autoload :NodeRegistry, "reactive_admin/node_registry"
  autoload :Provenance, "reactive_admin/provenance"
  autoload :Masking, "reactive_admin/masking"
  autoload :CompositeKeys, "reactive_admin/composite_keys"
  autoload :Degradation, "reactive_admin/degradation"
  autoload :ImplicitDefaults, "reactive_admin/implicit_defaults"
  autoload :HtmlNodes, "reactive_admin/html_nodes"
  autoload :HtmlRich, "reactive_admin/html_rich"
  autoload :HtmlPolicy, "reactive_admin/html_policy"
  autoload :MediaNodes, "reactive_admin/media_nodes"
  autoload :LayoutClasses, "reactive_admin/layout_classes"
  autoload :InlineStyle, "reactive_admin/inline_style"
  autoload :StyleSources, "reactive_admin/style_sources"
  autoload :StyleReport, "reactive_admin/style_report"
  autoload :Filters, "reactive_admin/filters"
  autoload :Auth, "reactive_admin/auth"
  autoload :Mcp, "reactive_admin/mcp"
  autoload :Authorizer, "reactive_admin/authorizer"
  autoload :Permissions, "reactive_admin/permissions"
  autoload :Actions, "reactive_admin/actions"
  autoload :Menu, "reactive_admin/menu"
  autoload :Exposure, "reactive_admin/exposure"
  autoload :ApiGuards, "reactive_admin/api_guards"
  autoload :MenuOverlay, "reactive_admin/menu_overlay"
  autoload :Site, "reactive_admin/site"
  autoload :ResourceSummary, "reactive_admin/resource_summary"
  autoload :ResourceMeta, "reactive_admin/resource_meta"
  autoload :ActionLinks, "reactive_admin/action_links"
  autoload :ActionItems, "reactive_admin/action_items"
  autoload :ServerTiming, "reactive_admin/server_timing"
  autoload :Manifest, "reactive_admin/manifest"
  autoload :IndexRecorder, "reactive_admin/index_recorder"
  autoload :IndexPayload, "reactive_admin/index_payload"
  autoload :ShowPayload, "reactive_admin/show_payload"
  autoload :ApiErrors, "reactive_admin/api_errors"
  autoload :ControllerExtension, "reactive_admin/controller_extension"
  autoload :Choices, "reactive_admin/choices"
  autoload :Location, "reactive_admin/location"
  autoload :BatchActions, "reactive_admin/batch_actions"
  autoload :FormRecorder, "reactive_admin/form_recorder"
  autoload :FormContent, "reactive_admin/form_content"
  autoload :FormField, "reactive_admin/form_field"
  autoload :DateBound, "reactive_admin/date_bound"
  autoload :FormHasMany, "reactive_admin/form_has_many"
  autoload :FormSchema, "reactive_admin/form_schema"
  autoload :FormPayload, "reactive_admin/form_payload"
  autoload :FormLock, "reactive_admin/form_lock"
  autoload :ScrubbedError, "reactive_admin/scrubbed_error"
  autoload :WriteAudit, "reactive_admin/write_audit"
  autoload :WriteGuards, "reactive_admin/write_guards"
  autoload :MaskedJson, "reactive_admin/masked_json"
  autoload :ValueToken, "reactive_admin/value_token"
  autoload :ParamNormalizer, "reactive_admin/param_normalizer"
  autoload :ErrorKeys, "reactive_admin/error_keys"
  autoload :RowErrors, "reactive_admin/row_errors"
  autoload :LookupAudit, "reactive_admin/lookup_audit"
  autoload :OptionsPayload, "reactive_admin/options_payload"
  autoload :LookupPayload, "reactive_admin/lookup_payload"
  autoload :LabelsPayload, "reactive_admin/labels_payload"
  autoload :OptionSource, "reactive_admin/option_source"
  autoload :OptionSources, "reactive_admin/option_sources"
  autoload :Search, "reactive_admin/search"
  autoload :Diagnostics, "reactive_admin/diagnostics"
  autoload :ResourceDSL, "reactive_admin/reactive_dsl"
  autoload :ResourceOptions, "reactive_admin/reactive_dsl"
  autoload :ReactiveDSL, "reactive_admin/reactive_dsl"
  autoload :Ladder, "reactive_admin/ladder"
  autoload :Frame, "reactive_admin/frame"
  autoload :Layouts, "reactive_admin/frame"
  autoload :Embed, "reactive_admin/embed"
  autoload :TemplateActions, "reactive_admin/template_actions"
  autoload :TemplateContent, "reactive_admin/template_content"
  autoload :TemplateForm, "reactive_admin/template_form"
  autoload :PageForms, "reactive_admin/page_forms"
  autoload :PagePayload, "reactive_admin/page_payload"
  autoload :PageControllerExtension, "reactive_admin/page_controller_extension"
  autoload :Doctor, "reactive_admin/doctor"
  autoload :LegacyInventory, "reactive_admin/legacy_inventory"
  autoload :IndexViews, "reactive_admin/index_views"
  autoload :IndexOptions, "reactive_admin/index_options"
  autoload :Sidebars, "reactive_admin/sidebars"
  autoload :RansackGuard, "reactive_admin/ransack_guard"
  autoload :QueryGuard, "reactive_admin/query_guard"
  autoload :RateLimit, "reactive_admin/rate_limit"
  autoload :CsvInjection, "reactive_admin/csv_injection"
  autoload :BackgroundRequests, "reactive_admin/background_requests"
  autoload :ApiFallback, "reactive_admin/api_fallback"
  autoload :OpenApi, "reactive_admin/open_api"
  autoload :Ui, "reactive_admin/ui"

  class << self
    def config = @config ||= Configuration.new

    def configure = yield(config)

    # True for requests the client marked as background; see BackgroundRequests.
    def background_request?(request) = BackgroundRequests.background?(request)

    def api_guards = config.api_guards

    # Registers the guard `api :name` refers to: `{ |user, request| true }` lets the request through.
    def api_guard(name, &guard)
      raise ArgumentError, "api_guard #{name.inspect} needs a block taking (user, request)" unless guard
      raise ArgumentError, "api_guard #{name.inspect} is built in" if ApiGuards::STATIC.include?(name.to_sym)

      api_guards[name.to_sym] = guard
    end

    # Menu placement overlay; see MenuOverlay. Define it in app/admin so it reloads with AA.
    def menu(&) = MenuOverlay.define(&)

    def current_user(controller)
      # A token request never reads the session, even to find out the token failed.
      env = controller.request.env
      return env[Auth::IDENTITY_ENV]&.user if env.key?(Auth::IDENTITY_ENV)
      return config.current_user.call(controller) if config.current_user

      controller.send(AA.current_user_method(Registry.namespace))
    end

    # What `meta_cache_key` says about the user, digested; asked once per request because hosts
    # derive it from queries.
    def user_fingerprint(controller)
      controller.instance_variable_get(:@reactiveadmin_fingerprint) ||
        controller.instance_variable_set(:@reactiveadmin_fingerprint,
          Digest::SHA256.hexdigest(config.meta_cache_key.call(current_user(controller)).to_json))
    end
  end
end

require "reactive_admin/typeahead"
require "reactive_admin/routes"
require "reactive_admin/engine"
