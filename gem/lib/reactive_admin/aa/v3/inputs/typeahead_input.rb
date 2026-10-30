module Formtastic
  module Inputs
    # A datalist in the classic admin; the API serves the same declaration as a searchable typeahead.
    class TypeaheadInput < DatalistInput
      include ReactiveAdmin::Typeahead::SourceCollection
    end
  end
end
