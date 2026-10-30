module ReactiveAdmin
  module OpenApi
    # The paths, schemas and tag of one resource, for the actions it defines and the user may take.
    # Declarations only: filters without option lists, scopes, sortable columns, the controls-only form.
    class ResourceDoc
      include Parts

      CELL_TYPES = {
        integer: %w[number], float: %w[number], decimal: %w[number], boolean: %w[boolean], date: %w[date],
        datetime: %w[datetime], time: %w[datetime], string: %w[text], text: %w[text], json: %w[json], jsonb: %w[json]
      }.freeze
      BATCH_INPUTS = {
        "text" => {type: "string"}, "textarea" => {type: "string"}, "select" => {type: "string"}, "number" => {type: "number"},
        "date" => {type: "string", format: "date"}, "boolean" => {type: "boolean"}
      }.freeze
      EMPTY_DECLARED = {filters: [], scopes: [], batch_actions: [], download_formats: []}.freeze

      attr_reader :paths, :schemas, :parameters

      def initialize(context, summary)
        @ctx = context
        @summary = summary
        @key = summary[:key]
        @config = Registry.find(@key)
        @permissions = summary[:permissions]
        @actions = summary[:actions].map(&:to_sym)
        @nested = Paths.nested?(@config)
        @plural = camel(@key)
        @singular = camel(@config.resource_name.singular)
        @paths = {}
        @schemas = {}
        @parameters = {}
      end

      def call
        Degradation.with_collection(resource: @key, action: "openapi") do
          probe
          list
          show
          forms
          destroy
          meta_endpoints
          custom_actions
          batch
          export
        end
        {tag: tag, paths:, schemas:, parameters:}
      end

      private

      def tag
        {name: @key, "x-displayName": @summary[:plural_label], description: "#{@summary[:plural_label]} (#{@summary[:label]}). Paths of a resource nested under a parent carry the parent's id."}
      end

      def probe
        controller = @ctx.probe(@config).controller
        @declared = guarded("declarations") { ResourceMeta.new(controller).declared } || EMPTY_DECLARED
        @static = guarded("page sizes") { ResourceMeta.new(controller).static } || {}
        @columns = guarded("index columns") { IndexPayload.new(controller).declared_columns } || []
        @controller = controller
      end

      # What the resource declares can fail to evaluate; the document then says less rather than nothing.
      def guarded(what)
        yield
      rescue => e
        Degradation.record(kind: :openapi_degraded, where: "openapi/#{@key}/#{what}", reason: "#{what.capitalize} raised #{e.class}; documented generically")
        nil
      end

      # Denied actions are left out: the server refuses them, so they are not part of the API's surface.
      def allowed?(action, permission = action) = @actions.include?(action) && @permissions[permission] && !ApiGuards.denies?(@config, action, permission)

      def id(name) = @ctx.ids.claim(name)

      # `names` are the actions the operation runs: what their guards say is part of it.
      def add(path, verb, operation, names: nil) = ((@paths[path] ||= {})[verb] = names ? operation.merge(guard_extensions(@config, names)) : operation)

      def tags = [@key]

      def parent = @summary[:belongs_to]

      def parent_params = (@nested ? [path_param(parent[:param], "Id of the parent #{parent[:parent].singularize.humanize.downcase}")] : [])

      def base = @base ||= Paths.api(Paths.collection(@config, parent_id: ("{#{parent[:param]}}" if @nested)))

      def flat = @flat ||= Paths.api(Paths.collection(@config))

      def options_path = Paths.api(Paths.options(@config))

      def record_path = "#{base}/{id}"

      def id_param = ref("parameters", "Id")

      # Reads

      def list
        add(base, "get", operation(
          id: id("list#{@plural}"), summary: "List #{@summary[:plural_label]}", tags:,
          description: "Filtered, scoped, sorted and paginated rows. #{columns_note}".strip,
          parameters: [*parent_params, *query_params, *page_params],
          responses: {200 => success("Rows of the page", schema_ref("#{@plural}IndexResponse"), degraded: true)}, errors: [400, 403]
        ), names: %w[index])
        @schemas["#{@singular}Row"] = row_schema
        @schemas["#{@plural}IndexResponse"] = {
          allOf: [schema_ref("IndexResponse"), {type: "object", properties: {resource: {const: @key}, rows: {type: "array", items: schema_ref("#{@singular}Row")}}}]
        }
      end

      def show
        return unless allowed?(:show)

        add(record_path, "get", operation(
          id: id("get#{@singular}"), summary: "Show a #{@summary[:label]}", tags:, parameters: [*parent_params, id_param],
          responses: {200 => shared("ShowOk")}, errors: [403, 404]
        ), names: %w[show])
      end

      def forms
        add_form("#{base}/new", "getNew#{@singular}Form", "Form for a new #{@summary[:label]}", [*parent_params], :new, :create)
        add_form("#{record_path}/edit", "getEdit#{@singular}Form", "Form to edit a #{@summary[:label]}", [*parent_params, id_param], :edit, :update)
        write_endpoints
      end

      def add_form(path, operation_id, summary, parameters, action, permission)
        return unless allowed?(action, permission)

        errors = parameters.include?(id_param) ? [403, 404] : [403]
        add(path, "get", operation(id: id(operation_id), summary:, tags:, parameters:, responses: {200 => shared("FormOk")}, errors:), names: [action, permission])
      end

      def meta_endpoints
        core_operation("/admin/{resource}/_meta", flat + "/_meta", "get#{@plural}Meta", "MetaOk", summary: "Metadata of #{@summary[:plural_label]}", errors: [403, 404])
        core_operation("/admin/{resource}/_options", flat + "/_options", "get#{@plural}Options", "OptionsOk", summary: "Search options for a filter or form control", errors: [403, 404])
        core_operation("/admin/{resource}/_options/lookup", flat + "/_options/lookup", "lookup#{@plural}Options", "LookupOk", summary: "Labels of selected option values", errors: [400, 403, 404])
        core_operation("/admin/{resource}/_labels", flat + "/_labels", "get#{@plural}Labels", "LabelsOk", summary: "Display names by id", errors: [400, 404]) unless @nested || ApiGuards.denies?(@config, "show")
        if @nested
          core_operation("/admin/{resource}/_options", "#{base}/_options", "get#{@plural}OptionsNested", "OptionsOk", summary: "Search options of a form under its parent", parent: true, errors: [403, 404])
          core_operation("/admin/{resource}/_options/lookup", "#{base}/_options/lookup", "lookup#{@plural}OptionsNested", "LookupOk", summary: "Labels of selected option values under the parent", parent: true, errors: [400, 403, 404])
        end
        value_path = @nested ? "#{base}/{id}/_value" : "#{flat}/{id}/_value"
        core_operation("/admin/{resource}/{id}/_value", value_path, "get#{@singular}Value", "ValueOk", summary: "Full value of a summarized or truncated field", parent: @nested, errors: [403, 404]) if allowed?(:show)
      end

      # Core's operation as a template, under a concrete path: its first sentence, and its parameters
      # defined once under components rather than for every resource.
      def core_operation(template, path, operation_id, response, summary:, errors:, parent: false)
        source = Core.operation(template, "get")
        parameters = source["parameters"].to_a.reject { it["name"] == "resource" || it["$ref"] == "#/components/parameters/Resource" }.map { hoist(source["operationId"], it) }
        parameters.unshift(*parent_params) if parent
        add(path, "get", operation(id: id(operation_id), summary:, tags:, description: source["description"].to_s.squish.split(/(?<=\.)\s/).first,
          parameters:, responses: {200 => shared(response)}, errors:))
      end

      def hoist(operation_id, parameter)
        return parameter if parameter.key?("$ref") || parameter["in"] == "path"

        name = "#{operation_id}#{camel(parameter["name"])}".camelize
        @parameters[name] = parameter
        ref("parameters", name)
      end

      def export
        return unless allowed?(:index) && @declared[:download_formats].include?("csv")

        add("#{base}.csv", "get", operation(
          id: id("export#{@plural}Csv"), summary: "Export #{@summary[:plural_label]} as CSV", tags:,
          description: "AA's streamed CSV export of every page of the current filters, scope and order. Masked attributes are replaced by a placeholder.",
          parameters: [*parent_params, *query_params],
          responses: {200 => success("text/csv attachment", {type: "string", format: "binary"}, type: "text/csv")}, errors: [400, 403]
        ), names: %w[index])
      end

      # Writes

      def write_endpoints
        %i[create update].each do |action|
          next unless allowed?(action)

          body, keys, submittable = write_body(action)
          unsupported = "This form can't be submitted through the API (it holds inputs only the classic admin carries); writes answer 422 `unsupported`." unless submittable
          note = [unsupported, attribute_note(action)].compact.join(" ").presence
          send(:"#{action}_endpoint", body, keys, note)
        end
      end

      def write_body(action)
        controller = @controller
        form = (@form ||= [guarded("form") do
          FormSchema.new(controller, @config.resource_class.new, controls_only: true).then { [it.sections, it.submittable?] }
        end]).first
        return [{type: "object", additionalProperties: {type: "object", additionalProperties: true}}, [], true] unless form

        writer = WriteSchema.new(@config, form.first, options_path:, reserved: ApiGuards.reserved_keys(@config, [action.to_s]))
        [writer.schema || {type: "object", additionalProperties: false}, writer.keys, form.last]
      end

      # What the attribute guards of this write say, in the channel the document is for.
      def attribute_note(action)
        names = [action.to_s]
        applicable = ApiGuards.attributes_of(@config).select { ApiGuards.applies?(it, names) }
        denied = ApiGuards.denied_attributes(@config, names)
        rest = applicable - denied
        [
          listing(denied, "Reserved for the classic admin and not accepted here: %s. A write that includes one answers 403 `api_denied`."),
          listing(rest.select { it.guard == :session_only }, "Accepted only from a signed-in session: %s. A token's write that includes one answers 403 `api_denied`."),
          *rest.reject(&:static?).map { "A write that includes #{ticks(it.attributes)} may be refused by the `#{it.name}` guard (403 `api_denied`)." }
        ].compact.join(" ").presence
      end

      def listing(declarations, template) = (template % ticks(declarations.flat_map(&:attributes).uniq) if declarations.any?)

      def ticks(names) = names.map { "`#{it}`" }.join(", ")

      def create_endpoint(body, keys, note)
        @schemas["#{@singular}CreateParams"] = params_schema(body, keys)
        add(base, "post", operation(
          id: id("create#{@singular}"), summary: "Create a #{@summary[:label]}", tags:, write: true, parameters: parent_params,
          description: ["Body: the form's controls under the resource's param key. Disabled and masked inputs are not accepted.", note].compact.join(" "),
          request_body: {required: true, content: json(schema_ref("#{@singular}CreateParams"))},
          responses: {201 => shared("Created")}, errors: [403, 422]
        ), names: %w[create])
      end

      def update_endpoint(body, keys, note)
        @schemas["#{@singular}UpdateParams"] = params_schema(body, keys).deep_merge(properties: {lock: schema_ref("FormLock")})
        add(record_path, "patch", operation(
          id: id("update#{@singular}"), summary: "Update a #{@summary[:label]}", tags:, write: true, parameters: [*parent_params, id_param],
          description: ["Same body as create, plus the `lock` token the edit form handed out (a mismatch is 409 `stale`).", note].compact.join(" "),
          request_body: {required: true, content: json(schema_ref("#{@singular}UpdateParams"))},
          responses: {200 => shared("Written")}, errors: [403, 404, 409, 422]
        ), names: %w[update])
      end

      def params_schema(body, keys)
        key = @config.param_key.to_s
        {description: "`#{key}` wraps the record's attributes.", **body, **({required: [key]} if keys.include?(key))}
      end

      def destroy
        return unless allowed?(:destroy)

        add(record_path, "delete", operation(
          id: id("delete#{@singular}"), summary: "Delete a #{@summary[:label]}", tags:, write: true, parameters: [*parent_params, id_param],
          responses: {200 => shared("Written")}, errors: [403, 404, 409, 422]
        ), names: %w[destroy])
      end

      # Custom actions: every declared member and collection action the user may take.

      def custom_actions
        declare_actions(@config.member_actions, member: true)
        declare_actions(@config.collection_actions, member: false)
      end

      def declare_actions(declarations, member:)
        declarations.sort_by { it.name.to_s }.each do |declaration|
          name = declaration.name.to_s
          next unless @ctx.authorized?(name.to_sym, @config.resource_class, @config)

          verbs = verbs_of(declaration)
          verbs.each { action_operation(name, it, member:, suffix: (camel(it) if verbs.size > 1)) unless ApiGuards.denies?(@config, name, verb: it) }
        end
      end

      def action_operation(name, verb, member:, suffix:)
        path = member ? "#{record_path}/#{name}" : "#{base}/#{name}"
        prefix = member ? @singular.camelize(:lower) : @plural.camelize(:lower)
        kind = member ? "Member" : "Collection"
        get = verb == "get"
        add(path, verb, operation(
          id: id("#{prefix}#{camel(name)}#{suffix}"), summary: "#{name.humanize} (#{kind.downcase} action)", tags:, write: !get,
          description: "#{kind} action `#{name}` of #{@summary[:plural_label]}. #{action_note(get)}",
          parameters: [*parent_params, *(member ? [id_param] : []), *([form_query_param] if get && Ladder.action(@config, name)&.get_form)],
          request_body: (ref("requestBodies", "ActionParams") unless get),
          responses: action_responses(get), errors: action_errors(get, verb, member)
        ), names: [name])
      end

      def action_note(get)
        return "Answers the action's template as a form, or 501 `unsupported` when it renders an html page (use the classic admin)." if get

        "The action's redirect and flash become the result; an alert or errors answer 422."
      end

      def action_responses(get)
        return {200 => ref("responses", "ActionResult")} unless get

        {200 => shared("FormOk"),
         501 => {description: "The action renders an html page the API can't describe (`unsupported`).", content: json(schema_ref("Error"))}}
      end

      def action_errors(get, verb, member) = [403, *(404 if member), *(422 unless get), *(409 if %w[put patch].include?(verb))]

      def batch
        actions = @declared[:batch_actions].reject { it[:api_denied] }
        return if actions.empty? || !allowed?(:index) || ApiGuards.denies?(@config, "batch_action")

        add("#{base}/batch_action", "post", operation(
          id: id("batch#{@plural}"), summary: "Run a batch action on #{@summary[:plural_label]}", tags:, write: true, parameters: parent_params,
          description: "Runs one of the batch actions the user may use over the selected ids: #{actions.map { "`#{it[:key]}`" }.join(", ")}.",
          request_body: {required: true, content: json({oneOf: actions.map { batch_schema(it) }})},
          responses: {200 => ref("responses", "ActionResult")}, errors: [403, 422]
        ), names: %w[batch_action])
      end

      def batch_schema(action)
        inputs = action[:inputs].to_h { [it[:name], {description: it[:label], **BATCH_INPUTS.fetch(it[:control], {type: "string"})}] }
        properties = {
          batch_action: {const: action[:key]},
          collection_selection: {type: "array", items: {type: "string"}, description: "Ids of the selected records."},
          **({batch_action_inputs: {type: "object", properties: inputs, additionalProperties: false}} if inputs.any?)
        }
        {type: "object", title: action[:label], description: action[:confirm], required: %w[batch_action collection_selection], properties:,
         "x-reactiveadmin-guard": action[:api_guard]}.compact
      end

      # Listing parameters

      def query_params = [filters_param, scope_param, order_param, views_param].compact

      def page_params
        sizes = [ReactiveAdmin.config.max_per_page, *@static[:per_page_options]].compact.max
        [{name: "page", in: "query", schema: {type: "integer", minimum: 1, default: 1}},
          {name: "per_page", in: "query", description: "Page size, capped at #{sizes}.",
           schema: {type: "integer", minimum: 1, maximum: sizes, default: @static[:default_per_page]}.compact}]
      end

      def filters = @declared[:filters].reject { Masking.attribute?(it[:name], @config) }

      def filters_param
        properties = filters.reduce({}) { |all, filter| all.merge(filter_properties(filter)) }
        deep_object("q", properties, description: "Ransack predicates of the declared filters; any other predicate is a 400.") if properties.any?
      end

      def filter_properties(filter)
        label = filter[:label]
        case filter[:control]
        when "text" then predicates(filter, {type: "string"})
        when "number" then predicates(filter, {type: "number"})
        when "date_range"
          {filter.dig(:range, :from) => {type: "string", format: "date", description: "#{label}, from"},
           filter.dig(:range, :to) => {type: "string", format: "date", description: "#{label}, up to"}}
        when "boolean" then {filter[:param] => {type: "boolean", description: label}}
        else {filter[:param] => choice_filter(filter)}
        end
      end

      def predicates(filter, type)
        list = filter[:predicates] || [{param: filter[:param], label: nil}]
        list.to_h { [it[:param], {description: [filter[:label], it[:label]].compact.join(" "), **type}] }
      end

      def choice_filter(filter)
        description = "#{filter[:label]}. Options are served by `GET #{filter[:options_path]}`."
        filter[:multiple] ? {type: "array", items: {type: "string"}, description:} : {type: "string", description:}
      end

      def scope_param
        scopes = @declared[:scopes]
        return if scopes.empty?

        default = @declared[:default_scope]
        {name: "scope", in: "query", description: ("Defaults to `#{default}`." if default), schema: {type: "string", enum: scopes.pluck(:id)}}.compact
      end

      def order_param
        keys = sortable.filter_map { |column, _| column[:sort_key] }.uniq
        return if keys.empty?

        {name: "order", in: "query", description: "`<sort_key>_asc` or `_desc`; any other key is a 400.", schema: {type: "string", enum: keys.flat_map { ["#{it}_asc", "#{it}_desc"] }}}
      end

      def views_param
        views = @static[:index_views]
        return unless views

        {name: "as", in: "query", description: "The index view to render.", schema: {type: "string", enum: views.pluck(:as)}}
      end

      def sortable = @columns.select { |column, attribute| column[:sortable] && !masked?(attribute) }

      def masked?(attribute) = attribute && Masking.attribute?(attribute, @config)

      # Rows

      def columns_note
        shown = @columns.reject { |_, attribute| masked?(attribute) }
        return "" if shown.empty?

        "Columns: #{shown.map { |column, _| "#{column[:label]} (`#{column[:key]}`#{", sortable" if column[:sortable]})" }.join(", ")}."
      end

      def row_schema
        cells = @columns.filter_map { |column, attribute| [column[:key], cell_schema(column, attribute)] unless masked?(attribute) }.to_h
        {allOf: [schema_ref("Row"), {type: "object", properties: {cells: {type: "object", properties: cells}}}]}
      end

      def cell_schema(column, attribute)
        description = "#{column[:label]}#{" (attribute `#{attribute}`)" if attribute}"
        types = cell_types(attribute)
        return {**schema_ref("Node"), description:} unless types

        {description:, allOf: [schema_ref("Node"), {properties: {type: {enum: [*types, "empty", "error"]}}}]}
      end

      # The node types an attribute's value becomes (Values.for); nil where it depends on the host's block.
      def cell_types(attribute)
        return unless attribute

        klass = @config.resource_class
        reflection = klass.reflect_on_association(attribute)
        return %w[ref text] if reflection && %i[belongs_to has_one].include?(reflection.macro)
        return if reflection
        return %w[ref] if attribute == klass.primary_key
        return %w[text] if klass.defined_enums.key?(attribute)

        CELL_TYPES[klass.columns_hash[attribute]&.type]
      end
    end
  end
end
