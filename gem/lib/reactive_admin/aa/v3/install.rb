module ReactiveAdmin
  module AA
    module V3
      # Extensions mixed into AA's classes. Idempotent: `to_prepare` runs them again on every reload.
      module Install
        def prepend_display_helper(mod) = prepend_once(::ActiveAdmin::ViewHelpers::DisplayHelper, mod)

        def prepend_tag(mod) = prepend_once(::Arbre::HTML::Tag, mod)

        def prepend_csv_builder(*mods) = mods.each { prepend_once(::ActiveAdmin::CSVBuilder, it) }

        # `dsl` joins the `register_page` block's DSL, `config` the page's registration object.
        def extend_page(dsl:, config:)
          ::ActiveAdmin::PageDSL.include(dsl)
          ::ActiveAdmin::Page.include(config)
        end

        def extend_resource(dsl:, config:)
          ::ActiveAdmin::ResourceDSL.include(dsl)
          ::ActiveAdmin::Resource.include(config)
        end

        # Registers the typeahead input for forms and filters and lets selects take a `source:`.
        def install_typeahead(source_collection)
          ::Formtastic::Inputs.autoload(:TypeaheadInput, "reactive_admin/aa/v3/inputs/typeahead_input")
          ::ActiveAdmin::Inputs::Filters.autoload(:TypeaheadInput, "reactive_admin/aa/v3/inputs/filters/typeahead_input")
          [::Formtastic::Inputs::SelectInput, ::ActiveAdmin::Inputs::Filters::SelectInput].each { it.prepend(source_collection) }
        end

        private

        def prepend_once(target, mod) = (target.prepend(mod) unless target.include?(mod))
      end
    end
  end
end
