module ReactiveAdmin
  # Option source behind a select-like control. Small sets are inlined into the payload;
  # large ones are searched through the resource's _options endpoint instead.
  module Choices
    SCAN_CAP = 1000

    module_function

    # Relations are searched in SQL. Anything else is evaluated to entries ([label, value] or
    # [label, value, hint], or the same as a hash), which `cache` (a key from `cache_key`) keeps for
    # options_cache_ttl so repeated searches don't rebuild them.
    # `policy` limits relations to what the current user may read.
    def for(collection, view, label: nil, value: nil, cache: nil, policy: false)
      cached(cache) do
        collection = view.instance_exec(&collection) if collection.is_a?(Proc)
        collection = collection.all if collection.is_a?(Class) && collection < ActiveRecord::Base
        if collection.is_a?(ActiveRecord::Relation)
          records(OptionSource.implicit(collection, label:, value:), view, collection, policy:)
        else
          pairs(collection, view, label, value)
        end
      end
    end

    # A registered source (by name or instance), refined by the input's `scope:`. Sources that
    # aren't backed by a relation are treated like any other collection.
    def source(source, view, scope: nil, object: nil, policy: false, cache: nil)
      source = ReactiveAdmin.option_sources[source] unless source.is_a?(OptionSource)
      cached(cache) do
        scoped = source.scoped(view, scope, object)
        scoped.is_a?(ActiveRecord::Relation) ? records(source, view, scoped, policy:) : pairs(scoped, view, source.label, source.value)
      end
    end

    # Distinct values of a plain column.
    def column(klass, name, view)
      scope = klass.unscope(:order).where.not(name => nil).distinct.select(name).reorder(name)
      records(OptionSource.implicit(scope, label: name, value: name), view, scope, policy: false)
    end

    def path(config, field, context, id: nil, parent_id: nil)
      "#{Paths.api(Paths.options(config, parent_id:))}?#{{field:, context:, id:}.compact.to_query}"
    end

    # Varies by everything an options list can depend on, including who is asking.
    def cache_key(config, context, field, view, id: nil, parent_id: nil)
      who = ReactiveAdmin.user_fingerprint(view.controller)
      ["reactiveadmin/options", Registry.route_key(config), context, field, parent_id, id, who].compact.join("/")
    end

    def option(label, value, hint: nil) = {label: CGI.unescapeHTML(label.to_s), value: value.to_s, hint: hint&.to_s}.compact

    def pair(item, view, label, value)
      case item
      when Array then (item.size > 2) ? item.first(3) : [item.first, item.last]
      when Hash then item.symbolize_keys.then { |h| [h[:label], h.fetch(:value, h[:label]), h[:hint]].compact }
      when ActiveRecord::Base then [label ? call(label, item) : Values.display_label(item, view), call(value || (item.class.primary_key.is_a?(Array) ? :to_param : :id), item)]
      else [item, item]
      end
    end

    def call(method, record) = method.respond_to?(:call) ? method.call(record) : record.public_send(method)

    def records(source, view, scope, policy:) = Records.new(scope, view, source:, policy: policy && source.policy?)

    def pairs(collection, view, label, value)
      Pairs.new(collection.is_a?(Hash) ? collection.to_a : Array(collection).map { pair(it, view, label, value) })
    end

    # Only pair lists are cached: relations are lazy and cheap to rebuild.
    def cached(key)
      ttl = ReactiveAdmin.config.options_cache_ttl.to_i
      key = nil unless ttl.positive?
      hit = Rails.cache.read(key) if key
      return Pairs.new(hit) if hit

      yield.tap { Rails.cache.write(key, it.entries, expires_in: ttl) if key && it.is_a?(Pairs) }
    end

    def encode_cursor(offset) = Base64.urlsafe_encode64(offset.to_s, padding: false)

    def decode_cursor(cursor)
      (Integer(Base64.urlsafe_decode64(cursor.to_s), exception: false) || 0).clamp(0..)
    rescue ArgumentError
      raise ApiErrors::BadRequest, "Invalid cursor"
    end

    # Shared contract: list(selected, limit), search(term, limit, cursor) and lookup(values).
    # list and search return {options:, truncated:, next_cursor:}; lookup returns just the options.
    class Pairs
      attr_reader :entries

      def initialize(entries)
        @entries = entries
      end

      # [label, value] only: what the classic admin's selects take.
      def pairs = @entries.map { it.first(2) }

      def truncated?(limit) = @entries.size > limit

      # The model whose records the options are, for auditing; literal lists have none.
      def model = nil

      def list(selected, limit)
        return {options: options(@entries), truncated: false} if @entries.size <= limit

        {options: lookup(selected), truncated: true}
      end

      def search(term, limit, cursor = nil)
        tokens = term.downcase.split
        hits = @entries.select { |entry| tokens.all? { |token| entry.any? { it.to_s.downcase.include?(token) } } }
        page(hits, limit, Choices.decode_cursor(cursor))
      end

      def lookup(values) = options(@entries.select { |_, value| values.include?(value.to_s) })

      private

      def page(hits, limit, offset)
        truncated = hits.size > offset + limit
        {options: options(hits.drop(offset).first(limit)), truncated:, next_cursor: (Choices.encode_cursor(offset + limit) if truncated)}.compact
      end

      def options(entries) = entries.map { |label, value, hint| Choices.option(label, value, hint:) }
    end

    class Records
      def initialize(scope, view, source:, policy: false)
        @relation = scope
        @view = view
        @source = source
        @policy = policy
      end

      def model = klass

      # Whether `list` would fall back to a typeahead, without building labels or looking up the selection.
      def truncated?(limit) = ordered.limit(limit + 1).to_a.size > limit

      def list(selected, limit)
        records = ordered.limit(limit + 1).to_a
        return {options: options(records), truncated: false} if records.size <= limit

        {options: lookup(selected), truncated: true}
      end

      def search(term, limit, cursor = nil)
        offset = Choices.decode_cursor(cursor)
        records, truncated = search_columns.any? ? by_columns(term, limit, offset) : scan(term, limit, offset)
        {options: options(records), truncated:, next_cursor: (Choices.encode_cursor(offset + limit) if truncated)}.compact
      end

      def lookup(values)
        return [] if values.empty?

        records = value_column ? scope.where(value_column => values).to_a : scope.limit(SCAN_CAP).select { values.include?(value_of(it).to_s) }
        options(records)
      end

      # Every option, for the classic admin which renders whole lists.
      def pairs = scope.map { [label_of(it), value_of(it)] }

      private

      # Resolved on first use: building filters for a resource's metadata must not query.
      def scope
        @scope ||= (@policy && Authorizer.for(@view.controller)&.scope(@relation)) || @relation
      end

      def klass = @relation.klass

      # Association targets arrive unordered: alphabetical is the least surprising order.
      def ordered = (scope.order_values.empty? && label_column) ? scope.order(label_column) : scope

      def options(records) = records.map { Choices.option(label_of(it), value_of(it), hint: hint_of(it)) }

      def label_of(record) = @source.label ? Choices.call(@source.label, record) : Values.display_label(record, @view)

      def value_of(record) = Choices.call(@source.value, record)

      def hint_of(record) = (Choices.call(@source.hint, record) if @source.hint)

      def label_column
        @label_column ||= @source.label.to_s if @source.label.is_a?(Symbol) && Search.text_column?(klass, @source.label)
      end

      def value_column
        @value_column ||= @source.value.to_s if !@source.value.respond_to?(:call) && klass.columns_hash.key?(@source.value.to_s)
      end

      def search_columns = @search_columns ||= Search.columns_for(klass, @source, label_column:)

      def by_columns(term, limit, offset)
        Search.new(ordered, columns: search_columns, value_column:).call(term, limit:, offset:)
      end

      # No column to search: match computed labels in Ruby, over a bounded window.
      def scan(term, limit, offset)
        tokens = term.downcase.split
        window = ordered.limit(SCAN_CAP + 1).to_a
        capped = window.size > SCAN_CAP
        ReactiveAdmin.diagnostics.record(:scan_capped, source: (@source.name || klass.name).to_s, cap: SCAN_CAP) if capped
        hits = window.first(SCAN_CAP).select { |record| tokens.all? { label_of(record).to_s.downcase.include?(it) } }
        [hits.drop(offset).first(limit), capped || hits.size > offset + limit]
      end
    end
  end
end
