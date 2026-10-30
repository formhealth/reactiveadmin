module ReactiveAdmin
  module Mcp
    # The tool set is generic: a dozen tools that take a resource key, not one tool per operation, so
    # the list stays small however many resources the host registers. Each tool is a thin translation
    # onto an API route; what the caller may see or do is decided there.
    module Tools
      Tool = Data.define(:name, :title, :description, :properties, :required, :annotations, :write, :fit, :handler) do
        def schema = {type: "object", properties:, required:, additionalProperties: false}

        def definition = {name:, title:, description:, inputSchema: schema, annotations:}
      end

      # What a handler works with: the API, and the paths and limits derived from the registry.
      class Context
        attr_reader :api

        def initialize(api) = @api = api

        def limit = ReactiveAdmin.config.mcp.max_response_bytes

        def config_for(args)
          Registry.find(args["resource"].to_s) || raise(ToolError.new("Unknown resource #{args["resource"].to_s.first(60).inspect}. Call list_resources for the valid keys.", code: "unknown_resource"))
        end

        def path(rest = nil) = Paths.api(File.join("/", ReactiveAdmin.config.namespace.to_s, rest.to_s))

        def collection_path(args)
          config = config_for(args)
          parent = args["parent_id"].presence&.to_s
          raise ToolError.new("#{args["resource"]} is nested under #{Registry.route_key(config.belongs_to_config.target)}; pass parent_id.", code: "parent_required") if Paths.nested?(config) && !parent

          Paths.api(Paths.collection(config, parent_id: (encode(parent) if parent)))
        end

        def member_path(args) = File.join(collection_path(args), encode(args["id"].presence || raise(ToolError, "id is required")))

        def page_path(args)
          page = Registry.find_page(args["page"].to_s) || raise(ToolError.new("Unknown page #{args["page"].to_s.first(60).inspect}. Call list_resources for the valid keys.", code: "unknown_page"))
          return path("_pages/#{page.underscored_resource_name}") unless Paths.nested?(page)

          parent = args["parent_id"].presence || raise(ToolError, "#{args["page"]} is nested; pass parent_id.")
          path("#{Registry.route_key(page.belongs_to_config.target)}/#{encode(parent)}/_pages/#{page.underscored_resource_name}")
        end

        def param_key(args) = config_for(args).param_key

        def encode(value) = ERB::Util.url_encode(value.to_s)
      end

      TYPES = {"string" => String, "integer" => Integer, "boolean" => [true, false], "object" => Hash, "array" => Array}.freeze
      RESOURCE = {type: "string", description: "Resource key from list_resources, e.g. \"posts\"."}.freeze
      ID = {type: "string", description: "Record id."}.freeze
      PARENT = {type: "string", description: "Parent record id, only for resources listed as nested_under another."}.freeze
      CONFIRM = {type: "boolean", description: "Must be true. Without it the call only explains what it would do."}.freeze
      QUERY = {type: "object", description: "Values for the GET form's fields (`query_fields`), nested by each field's `param`: {\"simulation\": {\"date\": \"2026-10-01\"}}. Only declared fields; the response shows the results."}.freeze
      LOCK = {type: "object", description: "The `lock` object from get_form, passed back unchanged. The update is refused if the record changed since."}.freeze

      @tools = {}

      class << self
        attr_reader :tools

        def all = tools.values

        def find(name) = tools[name.to_s]

        # Tools a caller's scopes allow: a token without the write scope isn't offered writes.
        def visible(identity)
          write_scope = ReactiveAdmin.config.mcp.write_scope
          all.select { !it.write || identity.allows?(write_scope) }
        end

        def call(tool, args, context)
          validate!(tool, args)
          payload = tool.handler.call(context, args)
          Output.render(payload, limit: context.limit, **tool.fit)
        end

        def define(name, title:, description:, properties: {}, required: [], write: false, destructive: false, idempotent: false, fit: {}, &handler)
          annotations = write ? {readOnlyHint: false, destructiveHint: destructive, idempotentHint: idempotent, openWorldHint: false} : {readOnlyHint: true, openWorldHint: false}
          tools[name.to_s] = Tool.new(name: name.to_s, title:, description:, properties:, required: required.map(&:to_s), annotations:, write:, fit:, handler:)
        end

        private

        def validate!(tool, args)
          raise ToolError, "Arguments must be an object." unless args.is_a?(Hash)

          missing = tool.required - args.keys
          raise ToolError, "Missing required argument#{"s" if missing.size > 1}: #{missing.join(", ")}." if missing.any?

          args.each do |key, value|
            spec = tool.properties[key.to_sym] or raise ToolError, "Unknown argument #{key.to_s.first(40).inspect}. This tool takes: #{tool.properties.keys.join(", ")}."
            expected = TYPES.fetch(spec[:type])
            raise ToolError, "Argument #{key} must be a #{spec[:type]}." unless Array(expected).any? { |type| type.is_a?(Module) ? value.is_a?(type) : value == type }
            raise ToolError, "Argument #{key} must be one of: #{spec[:enum].join(", ")}." if spec[:enum]&.exclude?(value)
          end
        end
      end

      ACTION_NAME = /\A\w+\z/
      QUERY_LIMIT = 50
      FILTER_NAME = /\A\w+\z/

      define :list_resources, title: "List admin resources", fit: {rows: :resources},
        description: "Lists the resources (record types) and pages this user may open, with what they can do (index, show, create, update, destroy). Start here." do |ctx, _|
        Shapes.resources(ctx.api.get!(ctx.path("_manifest")))
      end

      define :describe_resource, title: "Describe a resource",
        description: "Columns, filters (with the exact filter params to use in list_records), scopes, sorting, batch and collection actions, and the create form for one resource. Fetches one row to learn the columns and discards it; pass columns: false to skip that.",
        properties: {resource: RESOURCE, parent_id: PARENT, columns: {type: "boolean", description: "Default true."}}, required: [:resource] do |ctx, args|
        base = ctx.collection_path(args)
        meta = ctx.api.get!(File.join(base, "_meta"))
        can = Shapes.can(meta["permissions"], meta.dig("api_denied", "actions"))
        columns = optional { ctx.api.get!(base, per_page: 1)["columns"] } if can.include?("index") && args["columns"] != false
        form = optional { Shapes.form(ctx.api.get!(File.join(base, "new"))) } if can.include?("create")
        Shapes.meta(meta, columns:, form:)
      end

      define :list_records, title: "List records", fit: {rows: :records},
        description: "Lists records of a resource, newest per the default order. filters is an object of declared filter params to values, e.g. {\"title_cont\": \"smith\", \"created_at_gteq\": \"2026-01-01\"}; describe_resource lists them (undeclared ones are rejected). Results are paged: follow `next`.",
        properties: {resource: RESOURCE, parent_id: PARENT, filters: {type: "object", description: "Declared filter params to values."},
                     scope: {type: "string", description: "Scope id from describe_resource."}, order: {type: "string", description: "<sort>_asc or <sort>_desc, e.g. created_at_desc."},
                     page: {type: "integer", description: "1-based."}, per_page: {type: "integer", description: "Capped by the server."}}, required: [:resource] do |ctx, args|
        filters = args.fetch("filters", {})
        bad = filters.keys.grep_v(FILTER_NAME)
        raise ToolError, "Invalid filter name #{bad.first.to_s.first(40).inspect}." if bad.any?

        per_page = [args["per_page"].to_i.positive? ? args["per_page"] : 10, ReactiveAdmin.config.mcp.max_per_page].min
        query = {q: filters.presence, scope: args["scope"], order: args["order"], page: args["page"], per_page:}
        Shapes.index(ctx.api.get!(ctx.collection_path(args), query))
      end

      define :get_record, title: "Get a record", fit: {text: :sections},
        description: "One record's fields and sections as text, plus the custom actions available on it. Large json or text values are summarized; call reveal_value with their expand_path to read them.",
        properties: {resource: RESOURCE, id: ID, parent_id: PARENT}, required: %i[resource id] do |ctx, args|
        Shapes.show(ctx.api.get!(ctx.member_path(args)))
      end

      define :get_page, title: "Get a page", fit: {text: :sections},
        description: "A custom admin page (dashboards, reports) as text. Page keys are listed by list_resources. A page with a filter form lists its fields as `query_fields`; pass `query` to see the results for them.",
        properties: {page: {type: "string", description: "Page key."}, parent_id: PARENT, query: QUERY}, required: [:page] do |ctx, args|
        Shapes.page(read_view(ctx, ctx.page_path(args), args["query"]))
      end

      define :get_form, title: "Get a form",
        description: "The fields of the new-record form (omit id) or the edit form (pass id): each field's `key` (what create_record and update_record take in values), control, whether it is required, its current value and options. The edit form's `lock` is needed by update_record.",
        properties: {resource: RESOURCE, id: {type: "string", description: "Record id for the edit form; omit for the new form."}, parent_id: PARENT}, required: [:resource] do |ctx, args|
        path = args["id"].present? ? File.join(ctx.member_path(args), "edit") : File.join(ctx.collection_path(args), "new")
        Shapes.form(ctx.api.get!(path)).merge(mode: args["id"].present? ? "edit" : "new")
      end

      define :create_record, title: "Create a record", write: true,
        description: "Creates a record. values is an object keyed by the `key` of each field from get_form (nested rows go under the key of their section, as an array of objects). Fields the form doesn't offer are rejected.",
        properties: {resource: RESOURCE, parent_id: PARENT, values: {type: "object", description: "Field key to value."}}, required: %i[resource values] do |ctx, args|
        written ctx.api.call!("POST", ctx.collection_path(args), body: {ctx.param_key(args) => args["values"]}), args
      end

      define :update_record, title: "Update a record", write: true, idempotent: true,
        description: "Changes fields of one record. Send only the fields to change, keyed as in get_form, plus the `lock` from the same get_form call. A stale lock is refused: reload with get_form and review before retrying.",
        properties: {resource: RESOURCE, id: ID, parent_id: PARENT, values: {type: "object", description: "Field key to new value."}, lock: LOCK,
                     lock_version: {type: "string", description: "Shorthand for the lock of a model with lock_version."}}, required: %i[resource id values] do |ctx, args|
        lock = args["lock"] || ({field: "lock_version", value: args["lock_version"]} if args["lock_version"])
        written ctx.api.call!("PATCH", ctx.member_path(args), body: {ctx.param_key(args) => args["values"], :lock => lock}.compact), args
      end

      define :delete_record, title: "Delete a record", write: true, destructive: true, idempotent: true,
        description: "Deletes one record. Requires confirm: true. Hard to undo: confirm with the user first.",
        properties: {resource: RESOURCE, id: ID, parent_id: PARENT, confirm: CONFIRM}, required: %i[resource id] do |ctx, args|
        path = ctx.member_path(args)
        unconfirmed!(args, "delete #{args["resource"]}/#{args["id"]} (DELETE #{path}), which may not be reversible.")
        written ctx.api.call!("DELETE", path), args
      end

      define :run_action, title: "Run an action", write: true, destructive: true,
        description: "Runs a custom action: kind member (needs id), collection, or batch (needs ids and a key from describe_resource's batch_actions). Action keys come from get_record, get_page or describe_resource. inputs is sent as the JSON body exactly as given; for actions with a form, read it first with method: get and nest values under the param names it shows. A GET action with a filter form takes `query` (see `query_fields`). Anything but a GET requires confirm: true.",
        properties: {resource: RESOURCE, action: {type: "string", description: "Action key."}, kind: {type: "string", enum: %w[member collection batch]}, id: ID, ids: {type: "array", description: "Record ids for kind batch (at most 100)."},
                     parent_id: PARENT, inputs: {type: "object", description: "Request body."}, query: QUERY, method: {type: "string", enum: %w[get post put patch delete], description: "Defaults to the action's own method."},
                     confirm: CONFIRM}, required: %i[resource action kind] do |ctx, args|
        run_action(ctx, args)
      end

      define :field_options, title: "Search a field's options", fit: {rows: :options},
        description: "Typeahead for a filter or form field that has `search`: finds options by term, or resolves known values to labels. Pass the field's `search` value as field.",
        properties: {resource: RESOURCE, field: {type: "string", description: "The `search` value of a filter or form field."}, context: {type: "string", enum: %w[filter form], description: "Default filter."},
                     term: {type: "string"}, value: {type: "array", description: "Values to resolve to labels."}, id: {type: "string", description: "Record id when searching an edit form's field."},
                     limit: {type: "integer"}, parent_id: PARENT}, required: %i[resource field] do |ctx, args|
        query = {field: args["field"], context: args.fetch("context", "filter"), term: args["term"], value: args["value"]&.join(","), id: args["id"],
                 limit: [args["limit"] || 10, ReactiveAdmin.config.mcp.max_per_page].min}
        body = ctx.api.get!(File.join(ctx.collection_path(args), "_options"), query)
        {options: body["options"].map { it.slice("value", "label") }, truncated: body["truncated"] || nil}.compact
      end

      define :reveal_value, title: "Reveal a summarized value",
        description: "Reads the full value behind an `expand_path` returned by get_record, get_form or list_records (a long text or a json value shown only as a summary). Each reveal is audited as a view of that field. path reads one nested key, e.g. \"allergies.0\".",
        properties: {expand_path: {type: "string", description: "The expand_path exactly as returned."}, path: {type: "string", description: "Nested key, dotted."}}, required: [:expand_path] do |ctx, args|
        reveal(ctx, args)
      end

      class << self
        private

        def optional
          yield
        rescue ToolError
          nil
        end

        def written(body, args)
          {ok: true, record: ("#{args["resource"]}/#{body["id"] || args["id"]}" if body["id"] || args["id"]), message: body["message"]}.compact
        end

        def unconfirmed!(args, what)
          return if args["confirm"] == true

          raise ToolError.new("Not done: this would #{what} Nothing was changed. Ask the user to confirm, then call again with confirm: true.", code: "confirmation_required")
        end

        def run_action(ctx, args)
          name = args["action"]
          raise ToolError, "action must be a plain key like \"archive\"." unless ACTION_NAME.match?(name)

          kind = args["kind"]
          base = ctx.collection_path(args)
          known = action_info(ctx, args, base, name, kind)
          verb = (args["method"] || known["method"] || "post").upcase
          path = action_path(ctx, args, base, name, kind)
          body = args["inputs"]
          query = args["query"]
          raise ToolError, "query is for GET actions; pass inputs for the others." if query && verb != "GET"
          raise ToolError, "Pass query or inputs, not both." if query && body
          if kind == "batch"
            ids = args["ids"]&.map(&:to_s) || raise(ToolError, "kind batch needs ids.")
            raise ToolError, "A batch takes at most 100 ids." if ids.size > 100

            body = {batch_action: name, collection_selection: ids, batch_action_inputs: args["inputs"]}.compact
            verb = "POST"
          end
          unless verb == "GET" || reserved?(ctx, args, kind, name)
            ask = known["confirm"] ? " The app asks: #{known["confirm"].to_s.first(200).inspect}" : ""
            unconfirmed!(args, "run #{kind} action #{name} on #{args["resource"]}#{" (#{args["ids"].size} records)" if kind == "batch"} (#{verb} #{path}).#{ask}")
          end
          action_result(query ? read_view(ctx, path, query) : ctx.api.call!(verb, path, body:))
        end

        # A read with a query is held to the fields of the GET forms the same view declares without one.
        def read_view(ctx, path, query)
          body = ctx.api.get!(path)
          return body if query.blank?

          declared = Layout.query_fields(body).map { it["param"].delete_suffix("[]") }
          raise ToolError.new("This has no GET form, so it takes no query.", code: "no_query") if declared.empty?

          unknown = flatten_query(query).keys - declared
          raise ToolError, "Unknown query field #{unknown.first.first(60).inspect}. The form takes: #{declared.join(", ")}." if unknown.any?

          ctx.api.get!(path, query)
        end

        def flatten_query(value, prefix = nil)
          pairs = value.flat_map do |key, nested|
            name = prefix ? "#{prefix}[#{key}]" : key.to_s
            case nested
            when Hash then flatten_query(nested, name).to_a
            when Array, String, Numeric, true, false, nil then [[name.delete_suffix("[]"), nested]]
            else raise ToolError, "Query values are strings, numbers, booleans or lists of them."
            end
          end
          raise ToolError, "A query takes at most #{QUERY_LIMIT} fields." if pairs.size > QUERY_LIMIT

          pairs.to_h
        end

        # Not asked to confirm what can't run: the call goes on to the API, which refuses it with a pointer to the classic admin.
        def reserved?(ctx, args, kind, name)
          ApiGuards.denies?(ctx.config_for(args), *((kind == "batch") ? ["batch_action", name] : [name]))
        end

        def action_path(ctx, args, base, name, kind)
          case kind
          when "member" then File.join(ctx.member_path(args), name)
          when "collection" then File.join(base, name)
          else File.join(base, "batch_action")
          end
        end

        # What the app says about the action (its method, its confirmation text), from the same API the UI reads.
        def action_info(ctx, args, base, name, kind)
          return {} if args["confirm"] == true && (args["method"] || kind == "batch")

          found = case kind
          when "member" then ctx.api.get!(ctx.member_path(args)).then { [*it["actions"], *Layout.actions(it["layout"])] }
          when "collection" then ctx.api.get!(File.join(base, "_meta"))["action_items"]
          else ctx.api.get!(File.join(base, "_meta"))["batch_actions"]
          end
          Array(found).find { it["key"] == name } || {}
        rescue ToolError
          {}
        end

        def action_result(body)
          return Shapes.form(body, with_params: true) if body.is_a?(Hash) && body["form"]
          return Shapes.page(body) if body.is_a?(Hash) && body["layout"]

          {ok: body["ok"], message: body["message"], location: body.dig("location", "url")}.compact
        end

        def reveal(ctx, args)
          uri = URI.parse(args["expand_path"])
          root = ctx.path.chomp("/")
          valid = uri.host.nil? && uri.path.start_with?("#{root}/") && uri.path.end_with?("/_value") && uri.path.exclude?("..") && uri.path.exclude?("//")
          raise ToolError, "expand_path must be a path returned by a previous result, unchanged." unless valid

          query = Rack::Utils.parse_query(uri.query).slice("field", "token").merge("path" => args["path"])
          value = ctx.api.get!(uri.path, query)["value"]
          size = JSON.generate(value).bytesize
          return {value:} if size <= ctx.limit - 500

          {truncated: "The value is #{size} bytes, over the #{ctx.limit} byte limit. Pass path to read part of it.", kind: value.class.name.downcase,
           keys: (value.keys.first(20) if value.is_a?(Hash)), length: (value.size if value.is_a?(Array))}.compact
        rescue URI::InvalidURIError
          raise ToolError, "expand_path is not a valid path."
        end
      end
    end
  end
end
