module ReactiveAdmin
  module Mcp
    # Reduces the API's typed nodes to what an agent reads best: plain values for cells and rows, and
    # plain text for layout. Values the server withheld (masked, summarized, truncated) stay that way.
    module Layout
      BLOCKS = %w[group box columns column toolbar blockquote].freeze

      module_function

      def value(node)
        return node unless node.is_a?(Hash)

        case node["type"]
        when "empty" then nil
        when "text", "code" then text(node)
        when "number", "boolean", "date", "datetime" then node["value"]
        when "status" then node["label"]
        when "ref" then ref(node)
        when "link" then link(node)
        when "json" then json(node)
        when "masked" then "[masked]"
        when "error" then "[error: #{node["label"]}]"
        when "image" then "[image: #{node["alt"].presence || "no description"}]"
        when "document" then "[document: #{node["title"].presence || "PDF"}]"
        when "action" then action_text(node)
        when "html", "frame" then plain(node["html"])
        else node["text"] || node["label"] || node["type"]
        end
      end

      def text(node)
        return node["text"] unless node["truncated"]

        {text: node["text"], truncated: true, expand_path: node["expand_path"]}.compact
      end

      def ref(node)
        target = node["ref"]
        {ref: ("#{target["resource"]}/#{target["id"]}" if target), label: node["label"]}.compact
      end

      def link(node)
        return node["label"] unless node["external"] || node["ref"]

        node["external"] ? {label: node["label"], url: node["href"]} : ref(node)
      end

      def json(node)
        return node["value"] if node.key?("value")

        {summary: node["summary"], expand_path: node["expand_path"]}.compact
      end

      def plain(html)
        fragment = HtmlPolicy.parse(html) or return ""
        fragment.css("script, style").remove
        fragment.text.squish
      end

      def action_text(node)
        action = node["action"] || {}
        "[action #{action["key"]}: #{action["label"]}#{" (#{action["method"].to_s.upcase})" if action["method"]}]"
      end

      # One line for a node and everything inside it.
      def inline(node)
        return node["children"].map { inline(it) }.join.squish if node.is_a?(Hash) && node["children"]

        value(node).then { it.is_a?(String) ? it : it.to_json }
      end

      # Layout as markdown-ish text. `rows` skips attribute tables, which `attributes` reads as fields.
      def render(nodes, rows: true)
        Array(nodes).filter_map { block(it, rows) }.join("\n").strip
      end

      # Fields of the GET forms of a response (a page's layout, or a template's own form and its layout): the
      # ones a read may carry as a query. Fields the API refuses to write are no better to filter by.
      def query_fields(body)
        own = (body["action"]&.dig("method") == "get") ? Array(body.dig("form", "sections")).flat_map { it["fields"] || [] } : []
        (own + get_forms(body["layout"])).reject { it["param"].blank? || it["control"] == "html" }
      end

      def get_forms(nodes)
        Array(nodes).flat_map do |node|
          next [] unless node.is_a?(Hash)

          own = (node["type"] == "form" && node.dig("form", "action", "method") == "get") ? node["form"]["form"]["sections"].flat_map { it["fields"] || [] } : []
          own + get_forms(node["children"])
        end
      end

      # Label => value for every attributes table and definition list in the layout.
      def attributes(nodes)
        Array(nodes).flat_map { |node| collect(node) }.each_with_object({}) do |(label, value), fields|
          label = "#{label} (#{fields.size})" while fields.key?(label)
          fields[label] = value
        end
      end

      def collect(node)
        return [] unless node.is_a?(Hash)
        return node["rows"].map { |row| [row["label"], row_value(row["value"])] } if %w[attributes_table definition_list].include?(node["type"])

        Array(node["children"]).flat_map { collect(it) }
      end

      def row_value(nodes)
        values = Array(nodes).map { value(it) }
        if values.size == 1
          values.first
        else
          values.map { it.is_a?(String) ? it : it.to_json }.join(" ")
        end
      end

      def actions(nodes)
        Array(nodes).flat_map do |node|
          next [] unless node.is_a?(Hash)

          found = (node["type"] == "action" && node["action"]) ? [node["action"]] : []
          found + actions(node["children"])
        end
      end

      def block(node, rows)
        return unless node.is_a?(Hash)

        children = -> { render(node["children"], rows:).presence }
        case node["type"]
        when "panel", "tab" then titled(node["title"], children.call)
        when "tabs", *BLOCKS then children.call
        when "attributes_table", "definition_list" then rows ? table_rows(node) : nil
        when "table" then table(node)
        when "list" then list(node)
        when "heading" then "#{"#" * node.fetch("level", 2).to_i.clamp(1, 6)} #{inline(node)}"
        when "divider" then "---"
        when "disclosure" then [Array(node["summary_nodes"]).map { inline(it) }.join, children.call].compact_blank.join("\n").presence
        when "form" then form_text(node)
        when "iframe", "frame" then "[interactive content omitted: open it in the admin UI]"
        else inline(node).presence
        end
      end

      # A GET form reads like a query; any other form is for the UI. The response's own form has no payload.
      def form_text(node)
        return unless node["form"]

        (node.dig("form", "action", "method") == "get") ? "[filter form: its fields are the query_fields]" : "[interactive content omitted: open it in the admin UI]"
      end

      def titled(title, body) = (if body
                                   title.present? ? "## #{title}\n#{body}" : body
                                 end)

      def table_rows(node)
        lines = node["rows"].map { |row| "- #{row["label"]}: #{row_value(row["value"]).then { it.is_a?(String) ? it : it.to_json }}" }
        [("### #{node["title"]}" if node["title"].present?), *lines].compact.join("\n")
      end

      def table(node)
        header = node["headers"].join(" | ")
        lines = node["rows"].map { |cells| cells.map { |cell| cell.is_a?(Array) ? cell.map { inline(it) }.join(" ") : inline(cell) }.join(" | ") }
        [header, *lines].join("\n")
      end

      def list(node)
        node["children"].each_with_index.map do |item, index|
          "#{node["ordered"] ? "#{index + 1}." : "-"} #{Array(item["children"]).map { inline(it) }.join(" ")}"
        end.join("\n")
      end
    end
  end
end
