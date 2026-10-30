module ReactiveAdmin
  module Mcp
    # Keeps a tool result inside the byte budget, saying so when it cuts something. Long strings are
    # clipped first, then the rows (or text) the caller names are trimmed until the result fits.
    module Output
      STRING_LIMIT = 1_000
      MIN_TEXT = 200

      module_function

      def render(payload, limit:, rows: nil, text: nil)
        payload = clip(payload.except(text)).merge(payload.slice(text))
        payload = trim_rows(payload, rows, limit) if rows && size(payload) > limit
        payload = trim_text(payload, text, limit) if text && size(payload) > limit
        json = JSON.generate(payload)
        return json if json.bytesize <= limit

        "#{json.byteslice(0, limit).scrub("")}\n[truncated at #{limit} bytes: narrow the request]"
      end

      def size(payload) = JSON.generate(payload).bytesize

      def clip(value)
        case value
        when String then (value.length > STRING_LIMIT) ? "#{value[0, STRING_LIMIT]}... [#{value.length - STRING_LIMIT} more characters cut]" : value
        when Array then value.map { clip(it) }
        when Hash then value.transform_values { clip(it) }
        else value
        end
      end

      def trim_rows(payload, key, limit)
        rows = payload[key]
        keep = rows.size
        keep -= 1 while keep.positive? && size(payload.merge(key => rows.first(keep))) > limit - 300
        payload.merge(key => rows.first(keep), :truncated => "Showing #{keep} of #{rows.size} #{key} because the response limit was reached. Request a smaller per_page, add filters, or fetch a single record.")
      end

      def trim_text(payload, key, limit)
        text = payload[key].to_s
        room = [limit - size(payload.merge(key => "")) - 300, MIN_TEXT].max
        payload.merge(key => text.byteslice(0, room).scrub(""), :truncated => "#{key} cut at #{room} bytes of #{text.bytesize}; read single pages or fields for the rest.")
      end
    end
  end
end
