module ReactiveAdmin
  # The index presenter in effect (`?as=` picks one of several) and what it declares beyond its
  # block: view kind, title, blank slate, paging and download links.
  class IndexViews
    DEFAULT_GRID_COLUMNS = 3

    attr_reader :presenter

    def self.scopes_in_render_order(scopes) = scopes.group_by(&:group).values.flatten(1)

    def self.built_in = AA.index_renderers

    def self.custom?(renderer) = renderer.is_a?(Class) && !built_in.value?(renderer)

    def initialize(config, as: nil)
      @config = config
      @presenter = AA.page_presenter(config, :index, as.presence) || AA.page_presenter(config, :index)
    end

    def renderer
      @renderer ||= AA.index_renderer(presenter&.[](:as))
    end

    def name = AA.index_name(renderer).to_s

    # Custom IndexAs classes are rendered per record, so they read as a block view.
    def kind = self.class.built_in.key(renderer) || "block"

    def table? = kind == "table"

    def custom? = self.class.custom?(renderer)

    def grid_columns = (presenter&.[](:columns) || DEFAULT_GRID_COLUMNS).to_i

    def list
      presenters = AA.index_presenters(@config)
      return unless presenters.is_a?(Hash) && presenters.size > 1

      presenters.map do |as, item|
        {as: as.to_s, label: AA.t("index_list.#{as}", default: as.to_s.titleize), default: item.equal?(presenters.default)}
      end
    end

    def title(controller)
      title = presenter&.[](:title)
      title = controller.instance_exec(&title) if title.is_a?(Proc)
      title.to_s.presence
    end

    # [label, href] of the declared link, [nil, nil] when the resource declared none.
    def blank_slate(view)
      return unless presenter&.has_key?(:blank_slate_link)

      link = presenter[:blank_slate_link]
      html = view.instance_exec(&link) if link.is_a?(Proc)
      anchor = HtmlPolicy.parse(html.to_s)&.at_css("a[href]")
      {label: anchor&.text&.strip.presence, href: anchor&.[]("href")}
    end

    def paginator? = presenter&.fetch(:paginator, true) != false

    # AA offers a page-size selector only for a list; the page size itself stays the resource's.
    def per_page_options
      return unless presenter&.has_key?(:per_page)

      list = presenter[:per_page]
      list.is_a?(Array) ? list.map(&:to_i) : []
    end

    # The presenter's `download_links:`, then the resource's own, then the namespace's.
    def download_links
      return presenter[:download_links] if presenter&.has_key?(:download_links)

      resource = @config.download_links if @config.respond_to?(:download_links)
      resource.nil? ? @config.namespace.download_links : resource
    end
  end
end
