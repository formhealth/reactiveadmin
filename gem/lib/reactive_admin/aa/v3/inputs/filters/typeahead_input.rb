module ActiveAdmin
  module Inputs
    module Filters
      # Filter counterpart of ActiveAdmin::Inputs::TypeaheadInput; names its param like AA's select filters.
      class TypeaheadInput < ::Formtastic::Inputs::DatalistInput
        include Base
        include ReactiveAdmin::Typeahead::SourceCollection

        def input_name
          return method if seems_searchable?

          searchable_method_name + "_eq"
        end

        def searchable_method_name
          if searchable_has_many_through?
            "#{reflection.through_reflection.name}_#{reflection.foreign_key}"
          else
            name = method.to_s
            name.concat "_#{reflection.association_primary_key}" if reflection_searchable?
            name
          end
        end

        # Provide the AA translation to the blank input field.
        def include_blank
          I18n.t "active_admin.any" if super
        end

        def input_html_options_name = "#{object_name}[#{input_name}]"

        # The field is read from and named after the ransack predicate, not the attribute or association.
        def to_html
          @name = input_html_options[:id].gsub(/_id$/, "")
          input_wrapping { label_html << builder.text_field(input_name, input_html_options) << data_list_html }
        end

        # Without a source or collection, offer the distinct values of the column.
        def collection
          (!options[:source] && !options[:collection] && column) ? pluck_column : super
        rescue ActiveRecord::QueryCanceled => error
          raise ActiveRecord::QueryCanceled.new "#{error.message.strip} while querying the values for the ActiveAdmin :#{method} filter"
        end

        def pluck_column = klass.reorder("#{method} asc").distinct.pluck(method)

        def reflection_searchable? = reflection && !reflection.polymorphic?
      end
    end
  end
end
