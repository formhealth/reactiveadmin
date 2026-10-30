module ReactiveAdmin
  class ShowPayload
    # Arbre context mirroring ActiveAdmin::Views::Pages::Show#attributes_table.
    class Page < AA.arbre_element
      include PageForms::ArbreForms

      def attributes_table(*args, &block)
        options = args.extract_options!
        title = if options.key?(:title)
          AA.render_or_call(helpers, resource, options[:title])
        else
          AA.resource_text(active_admin_config, :details)
        end
        panel(title) { attributes_table_for(resource, *args, &block) }
      end

      # Never `attributes_table` with no columns: AA reads that as "all of them".
      def default_main_content(&)
        return ImplicitDefaults.blocked("show") if ImplicitDefaults.strict?

        columns = ImplicitDefaults.columns(active_admin_config, where: "show")
        helpers.reactiveadmin_implicit_text = ImplicitDefaults.text_columns(active_admin_config)
        attributes_table(*columns, &) if columns.any?
      end
    end

    def initialize(controller)
      @controller = controller
      @config = AA.config_of(controller)
      @view = ValuePayload.install(Masking.install(controller.view_context, @config), @config).extend(ImplicitDefaults::Display)
      @authorizer = Authorizer.for(controller)
    end

    def as_json(*)
      record = AA.resource(@controller)
      presenter = AA.page_presenter(@config, :show)
      links = ActionLinks.new(host: @controller.request.host, base_url: @controller.request.base_url, authorizer: @authorizer, subject: record)
      derived = Actions.new(@config, @authorizer, record, view: @view)
      generated = derived.as_json
      items = ActionItems.new(@controller, "show", subject: record).call(generated)
      Degradation.attach({
        resource: Registry.route_key(@config),
        id: record.to_param.to_s,
        paths: Paths.record(@config, record),
        title: title(record, presenter),
        display_name: Values.display_name(record, @view),
        permissions: Permissions.new(@config, @authorizer).record(record),
        actions: generated + items + derived.exposed(items),
        layout: NodeRegistry.with_scope { HtmlNodes.layout(render_layout(record, presenter, forms: true), src: Paths.record(@config, record)[:show], host: @controller.request.host, links:, resource: @config.resource_name) }
      }.merge(sidebars(record)))
    end

    # Attributes the page shows as symbol rows: the allowlist for `_value`.
    def rendered_attributes(record)
      render_layout(record, AA.page_presenter(@config, :show))
      @view.reactiveadmin_attributes
    end

    private

    def sidebars(record)
      list = Sidebars.new(@controller, "show", src: Paths.record(@config, record)[:show], subject: record).as_json
      list.any? ? {sidebars: list} : {}
    end

    def title(record, presenter)
      custom = presenter && presenter[:title]
      text = custom ? AA.render_or_call(@view, record, custom) : AA.display_name(@view, record)
      CGI.unescapeHTML(text.to_s)
    end

    # `forms` records the Formtastic forms of the block into form nodes; `_value` only needs the attributes.
    def render_layout(record, presenter, forms: false)
      page = new_page
      run = -> { presenter&.block ? page.instance_exec(record, &presenter.block) : page.default_main_content }
      forms ? PageForms.recording(@view, @controller, &run) : run.call
      page.arbre_context.to_s
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} show block fell back to defaults: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :show_block_failed, where: "show", reason: "Show block raised #{e.class}; showing default attributes")
      page = new_page
      page.default_main_content
      page.arbre_context.to_s
    end

    def new_page = AA.arbre_context(@controller.view_assigns, @view).insert_tag(Page)
  end
end
