module ReactiveAdmin
  # Typeahead matching over a relation (ILIKE on Postgres, LOWER() LIKE elsewhere): every token of the term must start a word in
  # at least one search column. Exact matches rank first, then prefix matches.
  class Search
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    TEXT_TYPES = %i[string text citext].freeze
    COMMON_COLUMNS = %i[name given_name family_name first_name last_name].freeze

    # Resolution order: source, the model's `reactive do search ... end`, the model itself, conventions.
    def self.columns_for(klass, source = nil, label_column: nil)
      names = source&.search || registered(klass) || (klass.reactive_admin_search_columns if klass.respond_to?(:reactive_admin_search_columns))
      names ||= [label_column, *AA.display_name_methods, *COMMON_COLUMNS]
      names.compact.map(&:to_s).uniq.select { text_column?(klass, it) }
    end

    def self.text_column?(klass, name) = klass.columns_hash[name.to_s]&.type&.in?(TEXT_TYPES) || false

    def self.registered(klass)
      AA.resource_for(Registry.namespace, klass)&.reactive_options&.[](:search)
    end

    def initialize(scope, columns:, value_column: nil)
      @scope = scope
      @columns = columns
      @value_column = value_column
      @klass = scope.klass
    end

    # Returns [records, truncated].
    def call(term, limit:, offset: 0)
      term = term.to_s.strip
      records = ranked(filtered(term), term).offset(offset).limit(limit + 1).to_a
      [records.first(limit), records.size > limit]
    end

    private

    def filtered(term)
      tokens = term.split
      return @scope if tokens.empty?

      match = tokens.map { token_match(it) }.reduce(:and)
      id = id_match(term)
      @scope.where(id ? match.or(id) : match)
    end

    def token_match(token)
      like = @klass.sanitize_sql_like(token)
      @columns.map { column(it) }.flat_map { [it.matches("#{like}%", nil, false), it.matches("% #{like}%", nil, false)] }.reduce(:or)
    end

    # Pasting an id finds its record, whichever column the label comes from.
    def id_match(term)
      [@value_column, (@klass.primary_key if @klass.primary_key.is_a?(String))].compact.uniq.filter_map do |key|
        type = @klass.type_for_attribute(key)
        column(key).eq(type.cast(term)) if (type.type == :uuid && term.match?(UUID)) || (type.type == :integer && term.match?(/\A\d+\z/))
      end.reduce(:or)
    end

    # DISTINCT scopes can only order by what they select.
    def ranked(scope, term)
      return scope if term.empty? || scope.distinct_value || @columns.empty?

      like = "#{@klass.sanitize_sql_like(term)}%"
      exact = @columns.map { "lower(#{quoted(it)}) = lower(:term)" }
      exact << "CAST(#{quoted(@value_column)} AS TEXT) = :term" if @value_column
      prefix = @columns.map { postgres? ? "#{quoted(it)} ILIKE :like" : "lower(#{quoted(it)}) LIKE lower(:like)" }
      rank = @klass.sanitize_sql_array(["CASE WHEN #{exact.join(" OR ")} THEN 0 WHEN #{prefix.join(" OR ")} THEN 1 ELSE 2 END", {term:, like:}])
      scope.reorder(Arel.sql(rank), *scope.order_values)
    end

    def postgres? = @klass.connection.adapter_name.match?(/postg/i)

    def column(name) = @klass.arel_table[name]

    def quoted(name) = "#{@klass.quoted_table_name}.#{@klass.connection.quote_column_name(name)}"
  end
end
