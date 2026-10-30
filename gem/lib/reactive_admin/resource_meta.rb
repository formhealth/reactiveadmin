module ReactiveAdmin
  # Everything a client needs to render and drive one resource's index: filters, scopes, batch
  # actions, header buttons. Built inside the resource's own controller so AA's procs reach its
  # helpers. Only what changes with code and permissions is cached; anything that can read
  # params or the request (`if:` procs, option lists, action items) is built per request.
  class ResourceMeta
    BOOT_ID = SecureRandom.hex(4)
    REVISION_VARS = %w[GIT_SHA GIT_COMMIT SOURCE_VERSION REVISION].freeze
    EXPORTABLE = %w[csv].freeze

    def self.fetch(controller) = new(controller).as_json

    # Without a configured version, code is assumed to change with the process (and with every
    # reload in development), which is safe but not shared between processes. `seed` identifies
    # what reloads: the resource's config, or whatever a document is built from.
    def self.code_version(seed)
      configured = ReactiveAdmin.config.meta_cache_version
      return configured.call if configured
      return seed.object_id if Rails.application.config.enable_reloading

      ENV.values_at(*REVISION_VARS).compact.first || BOOT_ID
    end

    def self.pagination_total?(config, presenter = AA.page_presenter(config, :index))
      config.paginate && presenter&.fetch(:pagination_total, true) != false
    end

    def initialize(controller)
      @controller = controller
      @config = AA.config_of(controller)
      @view = controller.view_context
      @authorizer = Authorizer.for(controller)
    end

    def cache_key
      ["reactiveadmin", "meta", Registry.route_key(@config), version, I18n.locale, ReactiveAdmin.user_fingerprint(@controller), ApiGuards.channel]
    end

    def as_json(*)
      static.merge(dynamic)
    end

    def static
      Rails.cache.fetch(cache_key, expires_in: ReactiveAdmin.config.meta_cache_ttl) do
        views = IndexViews.new(@config)
        ResourceSummary.new(@config, @authorizer).as_json.merge(
          per_page_options: views.per_page_options || Array(@config.per_page).map(&:to_i),
          default_per_page: Array(@config.per_page).first&.to_i || AA.default_per_page,
          default_order: @config.sort_order,
          pagination_total: self.class.pagination_total?(@config),
          **{index_views: views.list}.compact
        )
      end
    end

    def dynamic
      declared(options: true).merge(action_items:)
    end

    # What the resource declares, without action items. `options: false` also leaves out option lists,
    # so nothing is read from records.
    def declared(options: false)
      scopes = visible_scopes

      {
        filters: AA.filters_enabled?(@config) ? Filters.new(@config, @view, options:).call : [],
        batch_actions: BatchActions.new(@config, @view).as_json,
        scopes: IndexViews.scopes_in_render_order(scopes).map { scope_json(it) },
        default_scope: scopes.find { default_scope?(it) }&.id,
        download_formats:
      }
    end

    def download_formats
      links = IndexViews.new(@config, as: @controller.params[:as]).download_links
      links = safely(false, "download_links") { @view.instance_exec(&links) } if links.is_a?(Proc)
      formats = (links.is_a?(Array) && links.any?) ? links : (AA.default_download_formats(@config) unless links == false)
      Array(formats).map(&:to_s) & EXPORTABLE
    end

    private

    def version = self.class.code_version(@config)

    def action_items
      items = ActionItems.new(@controller, "index").call(generated_new)
      [*items, *Actions.new(@config, @authorizer, view: @view).exposed(items)]
    end

    # The client derives its New button from permissions; AA's own item would duplicate it.
    def generated_new
      return [] unless Registry.actions(@config).include?(:new)

      [{method: "get", href: File.join(@config.route_collection_path, "new")}]
    rescue ActionController::UrlGenerationError
      []
    end

    def scope_json(scope)
      {id: scope.id, name: scope_name(scope), count: nil}.merge(scope.group ? {group: scope.group.to_s} : {})
    end

    # Named block parameter: a bare `it` inside `safely`'s block would be that block's own argument.
    def visible_scopes = AA.scopes(@config).select { |scope| safely(true, "scope[#{scope.id}]") { AA.scope_visible?(@view, scope) } }

    def default_scope?(scope)
      block = scope.default_block
      safely(false, "scope[#{scope.id}]") { block.is_a?(Proc) ? @view.instance_exec(&block) : block }
    end

    def scope_name(scope) = safely(scope.id.humanize, "scope[#{scope.id}]") { AA.scope_name(@view, scope) }

    def safely(fallback, what)
      yield
    rescue => e
      Degradation.record(kind: :meta_block_failed, where: "index/#{what}", reason: "Block raised #{e.class}; used a default")
      fallback
    end
  end
end
