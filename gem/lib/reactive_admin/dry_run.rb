module ReactiveAdmin
  # What an update would change, worked out without saving. The submitted attributes are assigned and
  # validated inside a transaction that is always rolled back. Only validation callbacks run. The host's
  # `update` override, save callbacks and AA's update callbacks don't, so a failure only they would cause
  # isn't predicted.
  #
  # Rolling back undoes rows, not what callbacks did elsewhere (mail, jobs, uploads), and some writers
  # save at once on a persisted record: association and `*_ids` writers, attachments. So only database
  # columns whose writer is the one Rails generated, and nested rows built in memory, are previewed.
  # Anything else (virtual or stored attributes, a host-defined writer) is refused: a writer that isn't
  # Rails's own can do anything.
  #
  # Only attributes the form offers a control for are previewed, so a dry run can't read back a stored
  # value the form never exposes. A password or masked control withholds its value, and a JSON value is
  # shown only where the form would inline it, so their changes are masked like a configured secret.
  #
  # The diff names only the attributes the request submitted, so a value a callback derives from them
  # (and the form never offered) isn't shown.
  class DryRun
    MASKED = ValuePayload::MASK
    TEXT_LIMIT = 200
    LIST_LIMIT = 50
    NESTED = /_attributes\z/
    MULTIPARAMETER = /\(\d+[a-z]?\)\z/
    TOP_LEVEL_PARAM = /\A[^\[\]]+\[([^\[\]]+?)(?:\(\d+[a-z]?\))?\](?:\[\])?\z/

    Result = Data.define(:valid, :changes, :nested)

    def initialize(controller, record, sections)
      @config = AA.config_of(controller)
      @record = record
      fields = sections.flat_map { (it[:kind] == "has_many") ? [] : it[:fields].to_a }
      @offered = fields.filter_map { it[:param].to_s[TOP_LEVEL_PARAM, 1] }.to_set
      @withheld = fields.select { it[:control] == "password" || it[:masked] }.filter_map { it[:param].to_s[TOP_LEVEL_PARAM, 1] }.to_set
      @params = AA.resource_params(controller)
    end

    def call
      @params.each { refuse_unpreviewable(@record.class, it, @offered) }
      keys = @params.flat_map { it.keys.map { |key| key.to_s.sub(MULTIPARAMETER, "") } }.uniq
      nested, plain = keys.partition { nested?(@record.class, it) }
      result = nil
      @record.class.transaction(requires_new: true) do
        before = plain.index_with { read(it) }
        @record.assign_attributes(*@params)
        valid = @record.valid?
        result = Result.new(valid:, changes: diff(before, plain.index_with { read(it) }), nested: nested_changes(nested))
        raise ActiveRecord::Rollback
      end
      result
    end

    private

    def refuse_unpreviewable(klass, attributes, offered = nil)
      attributes.to_h.each do |key, value|
        key = key.to_s
        next if key == "_destroy"
        next refuse_unpreviewable_rows(klass, key, value) if nested?(klass, key)

        attribute = key.sub(MULTIPARAMETER, "")
        refuse(key) unless plain_column?(klass, attribute)
        refuse_unoffered(key) unless offered.nil? || offered.include?(attribute)
      end
    end

    # A column may itself end in `_attributes`; only a declared nested-attributes association is a section.
    def nested?(klass, key) = NESTED.match?(key) && klass.nested_attributes_options.key?(key.sub(NESTED, "").to_sym)

    def plain_column?(klass, key) = klass.columns_hash.key?(key) && generated_method?(klass, key) && generated_method?(klass, "#{key}=")

    def generated_method?(klass, writer)
      klass.define_attribute_methods
      return false unless klass.method_defined?(writer)

      owner = klass.instance_method(writer).owner
      owner.is_a?(ActiveRecord::AttributeMethods::GeneratedAttributeMethods) || owner == ActiveRecord::AttributeMethods::PrimaryKey ||
        klass.ancestors.any? { it.is_a?(Class) && it.respond_to?(:generated_association_methods) && it.generated_association_methods.equal?(owner) }
    end

    def refuse_unpreviewable_rows(klass, key, value)
      name = key.delete_suffix("_attributes").to_sym
      refuse(key) unless previewable_nested?(klass, name)

      reflection = klass.reflect_on_association(name)
      refuse(key) if sti?(reflection.klass)
      rows = value.respond_to?(:permitted?) ? value.to_h : value
      rows = (rows.key?("id") ? [rows] : rows.values) if reflection.collection? && rows.is_a?(Hash)
      Array.wrap(rows).each { refuse_unpreviewable(reflection.klass, it) if it.is_a?(Hash) || it.respond_to?(:permitted?) }
    end

    # A row's real class can be a subclass with its own writers, which the association's class doesn't reveal.
    def sti?(klass) = klass.columns_hash.key?(klass.inheritance_column.to_s)

    # A has_many builds its rows in memory unless the host hooks adding one. A has_one or belongs_to
    # replaces its current record at once, except where `update_only` assigns to it in place. A
    # `reject_if` other than `:all_blank`, or a `limit` given as a proc or method name, is host code that
    # runs on assignment.
    def previewable_nested?(klass, name)
      options = klass.nested_attributes_options[name] or return false
      reflection = klass.reflect_on_association(name) or return false
      return false unless generated_method?(klass, "#{name}_attributes=")
      return false unless [nil, ActiveRecord::NestedAttributes::ClassMethods::REJECT_ALL_BLANK_PROC].include?(options[:reject_if])

      return options[:update_only] unless reflection.collection?

      [Proc, Symbol].none? { options[:limit].is_a?(it) } && reflection.options.values_at(:before_add, :after_add).none?
    end

    # Names the field, never a value.
    def refuse(key) = raise(ApiErrors::BadRequest, "dry_run can't preview #{key}: setting it saves at once or runs code that can't be undone. Send the update without dry_run, or leave it out.")

    def refuse_unoffered(key) = raise(ApiErrors::BadRequest, "dry_run can't preview #{key}: the form doesn't offer it. Send the update without dry_run, or leave it out.")

    def read(key) = @record[key].as_json

    def diff(before, after)
      after.filter_map { |key, to| [key, {from: show(key, before[key]), to: show(key, to)}] if before[key] != to }.to_h
    end

    def show(key, value)
      return (MASKED if value.present?) if @withheld.include?(key) || Masking.attribute?(key, @config)

      case value
      when String then (value.size > TEXT_LIMIT) ? "#{value.first(TEXT_LIMIT)}... (#{value.size} characters)" : value
      when Hash, Array then structure(value)
      else value
      end
    end

    def structure(value)
      ValuePayload.inline?(value, @config) ? value : "[#{value.class.name.downcase}, #{value.to_json.bytesize} bytes]"
    end

    # Rows of has_many sections: counted, not diffed.
    def nested_changes(keys)
      keys.filter_map do |key|
        name = key.sub(NESTED, "")
        rows = Array.wrap(@record.association(name.to_sym).target)
        counts = {added: rows.count(&:new_record?), removed: rows.count(&:marked_for_destruction?), changed: rows.count { !it.new_record? && !it.marked_for_destruction? && it.changed_for_autosave? }}
        [name, counts] if counts.values.any?(&:positive?)
      rescue ActiveRecord::AssociationNotFoundError
        nil
      end.to_h
    end
  end
end
