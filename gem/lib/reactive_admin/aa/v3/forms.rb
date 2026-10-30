module ReactiveAdmin
  module AA
    module V3
      # AA's form builder and the Formtastic inputs behind it.
      module Forms
        def form_builder = ::ActiveAdmin::FormBuilder

        # The input Formtastic would render for `method`: AA's `as:` default unless `options[:as]` says otherwise.
        def build_input(builder, view, method, options)
          options[:as] ||= builder.send(:default_input_type, method, options)
          builder.send(:namespaced_input_class, options[:as]).new(builder, view, builder.object, builder.object_name, method, options)
        end

        # :check_boxes and :hidden inputs name their params differently from the rest.
        def input_kind(input)
          case input
          when ::Formtastic::Inputs::CheckBoxesInput then :check_boxes
          when ::Formtastic::Inputs::HiddenInput then :hidden
          end
        end

        # Columns `f.inputs` shows without a list: the model's, less `except` and what AA filters out.
        def default_form_columns(builder, except: nil)
          builder.send(:default_columns_for_object) - [*except, *filter_attributes]
        end
      end
    end
  end
end
