module ReactiveAdmin
  # A named, host-registered list of options (see ReactiveAdmin.option_sources). The relation is
  # kept lazy so the API can search it in SQL and the classic admin can still render all of it.
  class OptionSource
    attr_reader :name, :label, :value, :search, :hint

    def self.implicit(relation, label: nil, value: :id) = new(nil, relation, label:, value:)

    def initialize(name, relation, label: nil, value: :id, search: nil, hint: nil, policy: nil)
      @name = name&.to_sym
      @relation = relation
      @label = label
      @value = value || :id
      @search = Array(search).presence
      @hint = hint
      @policy = policy
    end

    # `refine` receives the relation (and, when it takes two arguments, the form object).
    def scoped(view, refine = nil, object = nil)
      base = relation(view)
      return base unless refine

      (refine.arity == 1) ? refine.call(base) : refine.call(base, object)
    end

    def policy? = @policy.nil? ? ReactiveAdmin.config.scope_options_by_policy : @policy

    private

    def relation(view)
      relation = @relation.respond_to?(:call) ? view.instance_exec(&@relation) : @relation
      relation.is_a?(Class) ? relation.all : relation
    end
  end
end
