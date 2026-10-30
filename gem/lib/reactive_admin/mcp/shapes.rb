module ReactiveAdmin
  module Mcp
    # Compact, agent-readable forms of the API's responses. Everything here is a reduction: nothing is
    # added to what the API already decided the caller may see.
    module Shapes
      OPTIONS_SHOWN = 15

      module_function

      def resources(manifest)
        menu = index_menu(manifest["menu"])
        resources = manifest["resources"].map do |resource|
          entry = menu[resource["key"]] || {}
          {
            key: resource["key"], label: resource["plural_label"], group: entry[:group] || resource["menu_parent"], description: entry[:description],
            can: can(resource["permissions"], resource.dig("api_denied", "actions")), nested_under: resource.dig("belongs_to", "parent")
          }.compact
        end
        pages = menu.values.select { it[:page] && !it[:api_denied] }.map { it.slice(:page, :label, :group, :description).compact }
        {user: manifest.dig("site", "current_user", "display_name"), resources:, pages:}
      end

      def meta(meta, columns: nil, form: nil)
        {
          key: meta["key"], label: meta["plural_label"], can: can(meta["permissions"], meta.dig("api_denied", "actions")), guarded: guarded(meta.dig("api_denied", "guards")),
          filters: meta["filters"].map { filter(it) },
          scopes: meta["scopes"].map { it.slice("id", "group").merge("name" => it["name"]).compact }, default_scope: meta["default_scope"],
          columns: columns&.map { |column| {key: column["key"], label: column["label"], sort: (column["sort_key"] if column["sortable"])}.compact },
          order: {default: meta["default_order"], format: "<sort>_asc or <sort>_desc"},
          per_page: {default: meta["default_per_page"]},
          batch_actions: usable(meta["batch_actions"]).map { batch_action(it) },
          actions: usable(meta["action_items"]).map { action(it) },
          downloads: meta["download_formats"],
          form:
        }.compact
      end

      def index(payload)
        meta = payload["meta"]
        rows = payload["rows"].map do |row|
          values = row["cells"].except("id").transform_values { Layout.value(it) }
          {id: row["id"], label: row["display_name"], values:}
        end
        page = meta.slice("page", "per_page", "total_count", "total_pages", "has_next_page").symbolize_keys
        page[:next] = {page: meta["page"] + 1} if meta["has_next_page"]
        {resource: payload["resource"], columns: payload["columns"].to_h { [it["key"], it["label"]] }, records: rows, **page,
         scope: meta["current_scope"], order: meta["order"], degraded: degraded(payload)}.compact
      end

      def show(payload)
        layout = payload["layout"]
        denied = summary(payload["resource"])
        {
          resource: payload["resource"], id: payload["id"], label: payload["display_name"], can: can(payload["permissions"], denied&.dig(:actions)), guarded: guarded(denied&.dig(:guards)),
          fields: Layout.attributes(layout).presence, sections: Layout.render(layout, rows: false).presence,
          actions: member_actions(payload["actions"], layout), degraded: degraded(payload)
        }.compact
      end

      def page(payload)
        layout = payload["layout"]
        {
          page: payload["key"], title: payload["title"], fields: Layout.attributes(layout).presence, sections: Layout.render(layout, rows: false).presence,
          query_fields: query_fields(payload), actions: usable([*payload["actions"], *Layout.actions(layout)]).map { action(it) }.presence, degraded: degraded(payload)
        }.compact
      end

      def form(payload, with_params: false)
        sections = payload["form"]["sections"]
        get = payload.dig("action", "method") == "get"
        {
          resource: payload["resource"], id: payload["id"], title: payload["title"], method: ("get" if get),
          fields: usable(sections.select { it["kind"] != "has_many" }.flat_map { it["fields"] }).map { field(it, with_params: with_params || get) },
          results: Layout.render(payload["layout"], rows: false).presence, query_fields: (query_fields(payload.except("action")) if payload["layout"]),
          nested: sections.select { it["kind"] == "has_many" }.map { nested(it) }.presence,
          lock: payload["lock"], submittable: payload["submittable"], unsupported_reason: payload["unsupported_reason"], degraded: degraded(payload)
        }.compact
      end

      # The fields of a response's GET forms, named as `query` of the read tools takes them.
      def query_fields(payload) = usable(Layout.query_fields(payload)).map { field(it, with_params: true) }.presence

      # `reserved` are the actions the host keeps in the classic admin: not offered, whatever the policy says.
      def can(permissions, reserved = nil) = permissions.to_h.select { |name, allowed| allowed && Array(reserved).exclude?(name) }.keys

      # What the API marks `api_denied` (an action, a form field) can't run through it, so it isn't offered.
      def usable(items) = Array(items).reject { it["api_denied"] }

      def summary(key) = ApiGuards.summary(Registry.find(key.to_s))

      # A registered guard decides per request, so what it covers is offered with a warning.
      def guarded(guards) = guards&.transform_values { "may be refused (#{it})" }

      def note(item) = ("may be refused (#{item["api_guard"]})" if item["api_guard"])

      def degraded(payload) = payload["degraded"]&.pluck("kind")&.uniq&.presence

      def index_menu(nodes, group = nil, found = {})
        nodes.each do |node|
          case node["kind"]
          when "group" then index_menu(node["children"], [group, node["label"]].compact.join(" > "), found)
          when "resource" then found[node["resource"]] = {group:, description: node["description"]}
          when "page" then found["page:#{node["page"]}"] = {page: node["page"], label: node["label"], group:, description: node["description"], api_denied: node["api_denied"]}
          end
        end
        found
      end

      def filter(filter)
        search = Rack::Utils.parse_query(URI(filter["options_path"]).query)["field"] if filter["options_path"]
        {
          name: filter["name"], label: filter["label"], control: filter["control"],
          params: filter["predicates"]&.pluck("param") || [filter["param"]].compact.presence,
          range: filter["range"]&.values_at("from", "to"),
          options: options(filter["options"]), search:
        }.compact
      end

      def options(list)
        return if list.blank?

        shown = list.first(OPTIONS_SHOWN).map { it.slice("value", "label") }
        (list.size > OPTIONS_SHOWN) ? shown + [{more: list.size - OPTIONS_SHOWN}] : shown
      end

      def batch_action(action)
        {key: action["key"], label: action["label"], confirm: action["confirm"], inputs: action["inputs"]&.map { input(it) }.presence, note: note(action)}.compact
      end

      def input(input) = {name: input["name"], label: input["label"], control: input["control"], options: options(input["options"])}.compact

      def action(action)
        {key: action["key"], label: action["label"], kind: action["kind"], method: action["method"], confirm: action["confirm"], enabled: (false if action["enabled"] == false), note: note(action)}.compact
      end

      def member_actions(actions, layout)
        shown = usable([*actions, *Layout.actions(layout)]).reject { %w[edit destroy].include?(it["kind"]) }
        shown.uniq { it["key"] }.map { action(it) }.presence
      end

      # `key` is what create_record and update_record take in `values`; `search` is the `field` for field_options.
      def field(field, with_params: false)
        key = param_key(field["param"])
        {
          key:, param: (field["param"] if with_params), label: field["label"], control: field["control"], required: field["required"] || nil,
          value: field["value"], multiple: field["multiple"], masked: field["masked"], summary: field["summary"], expand_path: field["expand_path"],
          options: options(field["options"]), search: (field["name"] if field["options_path"] || field["control"] == "typeahead"), help: field["hint"], note: note(field)
        }.compact
      end

      def nested(section)
        {key: section["param_key"], label: section["title"], allow_destroy: section["allow_destroy"], fields: usable(section["template_fields"]).map { field(it) },
         records: section["records"]&.size}.compact
      end

      # post[title] -> title, post[tag_ids][] -> tag_ids, post[rows][__INDEX__][body] -> body
      def param_key(param) = param.scan(/\[([^\]]*)\]/).flatten.reject(&:empty?).last || param
    end
  end
end
