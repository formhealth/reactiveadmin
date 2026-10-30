module ReactiveAdmin
  # A json value loaded for editing shows `[masked]` where a masked key holds a secret. A submitted
  # placeholder takes the stored value of the same key back; one with nothing to restore is dropped,
  # so the literal is never written.
  module MaskedJson
    module_function

    # Top-level json fields only: values inside has_many rows are never loaded for editing.
    def restore(params, fields, record, config)
      fields.each do |field|
        next unless field[:control] == "json" && field[:param]

        *path, leaf = field[:param].scan(/[^\[\]]+/)
        parent = path.inject(params) { |memo, key| memo.try(:[], key) }
        next unless parent.respond_to?(:key?) && parent.key?(leaf)

        parent[leaf] = restored(parent[leaf], stored(record, field[:name]), config)
      end
    end

    def restored(submitted, stored, config)
      structure = submitted.is_a?(String) ? parse(submitted) : plain(submitted)
      return submitted unless structure && JSON.generate(structure).include?(ValuePayload::MASK)

      result = walk(structure, stored, config)
      submitted.is_a?(String) ? JSON.generate(result) : result
    end

    def walk(submitted, stored, config)
      case submitted
      when Hash
        submitted.each_with_object({}) do |(key, value), out|
          if value == ValuePayload::MASK && Masking.attribute?(key, config)
            out[key] = stored[key] if stored.is_a?(Hash) && stored.key?(key)
          else
            out[key] = walk(value, stored.is_a?(Hash) ? stored[key] : nil, config)
          end
        end
      when Array then submitted.each_with_index.map { |value, i| walk(value, stored.is_a?(Array) ? stored[i] : nil, config) }
      else submitted
      end
    end

    def stored(record, name)
      value = record&.try(name)
      value.is_a?(String) ? parse(value) : value.as_json
    end

    def parse(text)
      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def plain(value)
      case value
      when ActionController::Parameters then value.to_unsafe_h.to_h
      when Hash, Array then value
      end
    end
  end
end
