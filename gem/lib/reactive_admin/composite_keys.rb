module ReactiveAdmin
  # AA's display-name fallback sends the primary key as a method name, which an array can't be.
  module CompositeKeys
    module DisplayName
      def display_name(resource)
        return super unless resource&.class.try(:primary_key).is_a?(Array) && AA.display_name_fallback?(self, resource)

        ERB::Util.html_escape("#{resource.class.model_name.human} ##{resource.to_param}")
      end
    end
  end
end
