require "forwardable"

module ReactiveAdmin
  module AA
    # One Formtastic input, read through the names FormField needs, so Formtastic's input API stays in the adapter.
    class Input
      extend Forwardable

      def_delegators :@input, :as, :method, :options, :input_name, :multiple?, :required?, :readonly?, :hint?, :hint_text,
        :localized_label, :humanized_method_name, :errors, :to_html, :collection, :raw_collection, :label_method, :value_method

      def initialize(input)
        @input = input
      end

      # :check_boxes and :hidden inputs name their params differently from the rest.
      def kind = AA.input_kind(@input)

      # Html attributes Formtastic derives from validations and columns (maxlength, min, max, step).
      def html_options = @input.input_html_options

      # Only association inputs have one.
      def association_primary_key = @input.try(:association_primary_key)
    end
  end
end
