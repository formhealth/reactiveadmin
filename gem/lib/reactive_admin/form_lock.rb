module ReactiveAdmin
  # Optimistic-lock token of a persisted record: Rails' own `lock_version` when the model has one,
  # else `updated_at`. `updated_at` doesn't move when only nested rows change, so a form with
  # has_many sections adds a digest of those rows' ids and timestamps to the token.
  class FormLock
    DIGEST_SEPARATOR = "~".freeze
    STALE_MESSAGE = "This record changed since you opened it.".freeze

    attr_reader :field

    def self.field_for(klass)
      if klass.locking_enabled? then "lock_version"
      elsif klass.column_names.include?("updated_at") then "updated_at"
      end
    end

    def self.for(record, nested: [])
      field = field_for(record.class) if record.persisted?
      new(record, field, nested:) if field && !record.public_send(field).nil?
    end

    def initialize(record, field, nested: [])
      @record = record
      @field = field
      @nested = (field == "updated_at") ? nested.to_a : []
    end

    def value
      current = @record.public_send(field)
      return current.to_s unless field == "updated_at"

      [current.utc.iso8601(6), (digest if @nested.any?)].compact.join(DIGEST_SEPARATOR)
    end

    def as_json(*) = {field:, value:}

    # `supplied` is the `lock` the client sent back: the object it was given, or just its value.
    def matches?(supplied)
      supplied = supplied.to_unsafe_h if supplied.respond_to?(:to_unsafe_h)
      supplied = supplied.stringify_keys if supplied.is_a?(Hash)
      sent_field, sent = supplied.is_a?(Hash) ? supplied.values_at("field", "value") : [nil, supplied]
      return false if sent_field && sent_field.to_s != field

      same_value?(sent.to_s)
    end

    private

    def same_value?(sent)
      return sent == value unless field == "updated_at"

      time, sent_digest = sent.split(DIGEST_SEPARATOR, 2)
      [Time.iso8601(time).utc.iso8601(6), sent_digest].compact.join(DIGEST_SEPARATOR) == value
    rescue ArgumentError
      false
    end

    # Read fresh: the association may hold rows loaded before another editor changed them.
    def digest
      rows = @nested.sort.map { |name| [name, nested_rows(@record.public_send(name))] }
      Digest::SHA256.hexdigest(rows.to_json)[0, 16]
    end

    def nested_rows(relation)
      klass = relation.klass
      stamp = klass.locking_column if klass.locking_enabled?
      stamp ||= "updated_at" if klass.column_names.include?("updated_at")
      relation.reorder(nil).pluck(*Array(klass.primary_key), *stamp).map { Array(it).map { |v| v.respond_to?(:utc) ? v.utc.iso8601(6) : v } }.sort_by(&:to_s)
    end
  end
end
