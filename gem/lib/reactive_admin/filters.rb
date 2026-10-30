module ReactiveAdmin
  # Translates a resource's AA `filter` declarations into manifest controls, mirroring
  # ActiveAdmin::Filters::FormBuilder#default_input_type and the Inputs::Filters::* param naming.
  class Filters
    TEXT_PREDICATES = %w[cont eq start end].freeze
    NUMBER_PREDICATES = %w[eq gt lt].freeze
    TYPES = {
      string: :string, text: :string, citext: :string,
      integer: :numeric, float: :numeric, decimal: :numeric,
      date: :date_range, datetime: :date_range, boolean: :boolean
    }.freeze

    # `options: false` leaves out option lists (which may read records); choice controls only point at `_options`.
    def initialize(config, view, options: true)
      @config = config
      @view = view
      @klass = config.resource_class
      @with_options = options
    end

    def call
      AA.filters(@config).filter_map do |attr, opts|
        next if skip?(opts)

        build(attr.to_s, opts)
      rescue => e
        Rails.logger.warn("[reactiveadmin] skipped filter #{attr} on #{@config.resource_name}: #{e.class}")
        Degradation.record(kind: :filter_dropped, where: "index/filter[#{attr}]", reason: "Filter raised #{e.class}; left out")
        nil
      end
    end

    def choices(name)
      declared = AA.filters(@config).find { |attr, _| attr.to_s == name }
      raise ActiveRecord::RecordNotFound, "No filter #{name}" unless declared

      choices_for(name, declared.last)
    end

    private

    def skip?(opts)
      (opts.key?(:if) && !AA.call_on(@view, @view, opts[:if])) ||
        (opts.key?(:unless) && AA.call_on(@view, @view, opts[:unless]))
    end

    def build(name, opts)
      type = (opts[:as] || default_type(name))&.to_sym or return
      base = {name:, label: label(name, opts)}

      case type
      when :string, :text then base.merge(control: "text", **predicates(name, TEXT_PREDICATES, single: type == :text))
      when :numeric then base.merge(control: "number", **predicates(name, NUMBER_PREDICATES))
      when :date_range, :date_picker then base.merge(control: "date_range", range: {from: "#{name}_gteq", to: "#{name}_lteq"})
      when :boolean then base.merge(control: "boolean", param: searchable?(name) ? name : "#{name}_eq", options: boolean_options)
      when :select then choice(base, "select", name, opts)
      when :check_boxes then choice(base, "checkboxes", name, opts)
      when :datalist, :typeahead then choice(base, "typeahead", name, opts)
      else raise ArgumentError, "unsupported filter type #{type}"
      end
    end

    def default_type(name)
      if name.match?(/_(eq|cont|start|end)\z/) then :string
      elsif @klass._ransackers.key?(name) then TYPES[@klass._ransackers[name].type]
      elsif reflection(name) || polymorphic_foreign_key?(name) then :select
      elsif (column = @klass.columns_hash[name]) then TYPES[column.type]
      end
    end

    def label(name, opts)
      label = opts[:label]
      label = label.call if label.is_a?(Proc)
      (label || @klass.human_attribute_name(name)).to_s
    end

    def predicates(name, list, single: false)
      return {param: name} if single || name.match?(/_(eq|cont|start|end|gt|lt)\z/)

      {predicates: list.map { {param: "#{name}_#{it}", label: I18n.t("ransack.predicates.#{it}", default: it).capitalize} }}
    end

    def boolean_options = [{label: "Yes", value: "true"}, {label: "No", value: "false"}]

    # Option lists backed by a relation are searched through the _options endpoint rather than
    # queried here: the metadata of a resource with many such filters would otherwise run one
    # query per filter on every cold load.
    def choice(base, control, name, opts)
      param = (control == "checkboxes") ? checkboxes_param(name) : choice_param(name, opts)
      base = base.merge(param:, **(param.end_with?("_in") ? {multiple: true} : {}))
      return base.merge(control:, options_path: Choices.path(@config, name, "filter")) unless @with_options

      source = choices_for(name, opts)
      listing = source.list([], ReactiveAdmin.config.inline_options_limit) unless source.is_a?(Choices::Records)
      if listing.nil? || listing[:truncated]
        base.merge(control: "typeahead", options: selected(source, base[:param]), options_path: Choices.path(@config, name, "filter"))
      else
        base.merge(control:, options: listing[:options])
      end
    rescue => e
      Rails.logger.warn("[reactiveadmin] no options for filter #{name} on #{@config.resource_name}: #{e.class}")
      Degradation.record(kind: :filter_options_failed, where: "index/filter[#{name}]", reason: "Filter options raised #{e.class}; shown without options")
      base.merge(control:, options: [])
    end

    # A typeahead only carries the options that are currently selected; the rest are searched.
    def selected(source, param)
      values = Array(@view.params.dig(:q, param)).map(&:to_s).compact_blank
      values.any? ? source.lookup(values) : []
    end

    def choice_param(name, opts)
      return name if searchable?(name)

      ref = reflection(name)
      key = (ref && !ref.polymorphic?) ? "#{name}_#{ref.association_primary_key}" : name
      key + (opts[:multiple] ? "_in" : "_eq")
    end

    # AA's check_boxes input always filters with `_in`, on the association's foreign key or ids.
    def checkboxes_param(name)
      return name if searchable?(name)

      ref = reflection(name)
      key = if ref.nil? then name
      elsif through?(ref) then "#{ref.through_reflection.name}_#{ref.foreign_key}"
      elsif ref.collection? then "#{name.singularize}_ids"
      else ref.foreign_key
      end
      "#{key}_in"
    end

    def through?(ref)
      ref.options[:through] && @klass.ransackable_associations.include?(ref.name.to_s) &&
        ref.through_reflection.klass.ransackable_attributes.include?(ref.foreign_key)
    rescue
      false
    end

    def choices_for(name, opts)
      ref = reflection(name)
      value = ref&.association_primary_key || :id
      cache = Choices.cache_key(@config, "filter", name, @view)
      return Choices.source(opts[:source], @view, scope: opts[:scope], policy: true, cache:) if opts[:source]
      return Choices.for(opts[:collection], @view, value:, cache:, policy: true) if opts[:collection]
      return Choices.for(ref.klass, @view, value:, policy: true) if ref && !ref.polymorphic?

      @klass.columns_hash.key?(name) ? Choices.column(@klass, name, @view) : Choices.for([], @view)
    end

    def reflection(name) = @klass.reflect_on_association(name)

    def polymorphic_foreign_key?(name)
      @klass.reflect_on_all_associations.any? { it.macro == :belongs_to && it.options[:polymorphic] && it.foreign_type == name }
    end

    # Ransack already understands names that carry a predicate or are exposed scopes.
    def searchable?(name)
      return false if @klass.columns_hash.key?(name)

      Ransack::Predicate.detect_from_string(name).present? ||
        Ransack::Context.for(@klass).ransackable_scope?(name, @klass)
    end
  end
end
