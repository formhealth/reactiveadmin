module Admin
  # Allows everything, including custom actions (`publish?`, `flag?`, ...), unless a resource policy narrows it.
  class DefaultPolicy
    attr_reader :user, :record

    def initialize(user, record)
      @user = user
      @record = record
    end

    def method_missing(name, *)
      name.end_with?("?") || super
    end

    def respond_to_missing?(name, include_private = false) = name.end_with?("?") || super

    class Scope
      def initialize(user, scope)
        @user = user
        @scope = scope
      end

      def resolve = @scope
    end
  end
end
