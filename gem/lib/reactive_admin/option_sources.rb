module ReactiveAdmin
  # Registry behind `ReactiveAdmin.option_sources { source :users, -> { User.all }, ... }`.
  class OptionSources
    def initialize
      @sources = {}
    end

    def source(name, relation, **) = @sources[name.to_sym] = OptionSource.new(name, relation, **)

    def [](name) = @sources.fetch(name.to_sym) { raise KeyError, "unknown option source #{name.inspect}" }

    def names = @sources.keys
  end
end
