module ReactiveAdmin
  module OpenApi
    # operationIds are unique across the document; a clash gets a counter, in build order, so ids stay stable.
    class OperationIds
      def initialize
        @taken = Set.new
      end

      def claim(base)
        id = base
        count = 1
        id = "#{base}#{count += 1}" while @taken.include?(id)
        @taken << id
        id
      end
    end
  end
end
