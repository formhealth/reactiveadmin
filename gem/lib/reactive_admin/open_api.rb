require "yaml"

module ReactiveAdmin
  # A typed OpenAPI 3.1 document of the admin API this app serves, for a docs viewer. It is derived
  # from what the manifest and the runtime use (resource summaries, filters, scopes, the controls-only
  # write schema), filtered by the user's permissions, and states only what the code declares: never
  # record data, option values, or anything masked, hidden or not exposed. Core's component schemas
  # (openapi/core.yaml) are embedded and referenced.
  module OpenApi
    SPEC_VERSION = "3.1.0"

    autoload :Core, "reactive_admin/open_api/core"
    autoload :Builder, "reactive_admin/open_api/builder"
    autoload :Context, "reactive_admin/open_api/context"
    autoload :Parts, "reactive_admin/open_api/parts"
    autoload :ResourceDoc, "reactive_admin/open_api/resource_doc"
    autoload :PageDoc, "reactive_admin/open_api/page_doc"
    autoload :WriteSchema, "reactive_admin/open_api/write_schema"
    autoload :Security, "reactive_admin/open_api/security"
    autoload :OperationIds, "reactive_admin/open_api/operation_ids"

    module_function

    # `user` limits the document to what they may do. `full` (the default without a user) describes the
    # whole exposed surface, for the rake task: never serve it.
    # `channel` (:session or :token) decides which of the `api` guards leave an operation out; a full
    # document and one built outside a request describe the session's.
    def build(user = nil, controller: nil, full: user.nil?, channel: nil) = Builder.new(user, controller:, full:, channel:).call

    # Cached like `_meta`: per code version, locale, permission fingerprint and auth channel.
    def fetch(controller)
      channel = ApiGuards.channel_of(controller.request)
      key = ["reactiveadmin", "openapi", ResourceMeta.code_version(Registry.index), I18n.locale, ReactiveAdmin.user_fingerprint(controller), channel]
      Rails.cache.fetch(key, expires_in: ReactiveAdmin.config.meta_cache_ttl) do
        build(ReactiveAdmin.current_user(controller), controller:, full: false, channel:)
      end
    end

    def to_yaml(document) = YAML.dump(document.deep_stringify_keys)
  end
end
