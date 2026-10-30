module ReactiveAdmin
  # Which index options a resource uses, for the doctor: what its registration declares, and
  # what a sampled index response shows of the index block (which only a run reveals).
  module IndexOptions
    PRESENTER_OPTIONS = %i[title blank_slate_link row_class per_page paginator download_links pagination_total scope_count].freeze

    module_function

    def declared(config)
      presenters = presenters(config)
      sidebars = AA.sidebar_sections(config).reject { Sidebars::BUILT_IN.include?(it.name) }
      {
        scope_groups: AA.scopes(config).filter_map(&:group).uniq.size,
        sidebars: sidebars.size,
        extra_views: (presenters.size - 1 if presenters.size > 1),
        custom_index_as: presenters.count { IndexViews.custom?(it[:as]) },
        check_boxes_filters: AA.filters(config).count { |_, opts| opts[:as] == :check_boxes },
        order_by: config.ordering.size,
        **PRESENTER_OPTIONS.to_h { |option| [option, presenters.count { it.has_key?(option) }] }
      }.reject { |_, count| count.to_i.zero? }
    end

    def sampled(payload)
      meta = payload["meta"]
      columns = payload["columns"]
      {
        default_actions_off: (1 if meta["default_row_actions"] == false && meta["view"] == "table"),
        row_actions_menu: (1 if meta["row_actions_dropdown"]),
        index_column: columns.count { it["kind"] == "index" },
        column_classes: columns.count { it["class_name"] },
        aligned_columns: columns.count { it["align"] },
        row_tones: payload["rows"].count { it["tone"] }
      }.reject { |_, count| count.to_i.zero? }
    end

    def presenters(config)
      list = AA.index_presenters(config)
      list.is_a?(Hash) ? list.values : Array(list)
    end
  end
end
