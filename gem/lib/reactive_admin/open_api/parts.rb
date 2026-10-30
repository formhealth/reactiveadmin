module ReactiveAdmin
  module OpenApi
    # Building blocks shared by the resource and page documents.
    module Parts
      VERBS = %w[get put post patch delete].freeze
      ERRORS = {
        400 => "BadRequest", 401 => "Unauthorized", 403 => "Forbidden", 404 => "NotFound",
        409 => "Conflict", 422 => "Invalid", 429 => "RateLimited"
      }.freeze
      DEGRADED = {"X-Reactiveadmin-Degraded": {"$ref": "#/components/headers/Degraded"}}.freeze

      module_function

      def ref(kind, name) = {"$ref": "#/components/#{kind}/#{name}"}

      def schema_ref(name) = ref("schemas", name)

      def shared(name) = ref("responses", name)

      def json(schema) = {"application/json": {schema:}}

      def success(description, schema, degraded: false, type: "application/json")
        {description:, **({headers: DEGRADED} if degraded), content: {type => {schema:}}}.compact
      end

      def error_responses(codes) = codes.sort.to_h { [it.to_s, ref("responses", ERRORS.fetch(it))] }

      # Query parameter for a deepObject map, e.g. `q[title_cont]=x`.
      def deep_object(name, properties, description:)
        {name:, in: "query", style: "deepObject", explode: true, description:,
         schema: {type: "object", properties:, additionalProperties: false}}
      end

      # A GET form's fields depend on what its view renders, which a document built from declarations can't read: the
      # operation takes them as free-form query parameters named by the form's field params, e.g. `simulation[date]`.
      def form_query_param
        {name: "form_fields", in: "query", style: "form", explode: true, required: false,
         description: "Fields of the view's GET form, named by each field's `param` (`simulation[date]=2026-10-01`; lists as `tags[]`). The response's `form` nodes list them with their current values.",
         schema: {type: "object", additionalProperties: true}}
      end

      def path_param(name, description = nil) = {name:, in: "path", required: true, description:, schema: {type: "string"}}.compact

      def camel(name) = name.to_s.camelize

      # An operation, with the standard error responses for the codes it can answer. Reads inherit the
      # document's security; writes also need the CSRF token.
      def operation(id:, summary:, tags:, responses:, write: false, description: nil, parameters: nil, request_body: nil, errors: [])
        {
          operationId: id, summary:, description:, tags:, parameters: parameters.presence, requestBody: request_body,
          responses: responses.merge(error_responses([401, 429, *errors].uniq)).sort_by { |code, _| code.to_s }.to_h,
          security: (Security.requirement(write: true) if write)
        }.compact
      end

      # What the guards of an action say of its operation: a session-only one, or one a registered guard may refuse.
      def guard_extensions(config, names)
        names = names.map(&:to_s)
        custom = ApiGuards.custom_for(config, names)
        {"x-reactiveadmin-session-only": (true if ApiGuards.session_only?(config, names)), "x-reactiveadmin-guard": custom&.name}.compact
      end

      # Verbs of a declared action (`member_action :x, method: [:get, :post]`).
      def verbs_of(declaration)
        Array.wrap(declaration.http_verb).map { it.to_s.downcase } & VERBS
      end

      error = ->(description) { {description:, content: json(schema_ref("Error"))} }
      # Responses every resource repeats, defined once under components.
      RESPONSES = {
        "Unauthorized" => error.call("Not signed in (`unauthorized`)."),
        "Forbidden" => error.call("The user may not do this (`forbidden`), a bearer token lacks the scope (`insufficient_scope`), or an `api` guard refuses it (`api_denied`, with `guard` and `classic_url`)."),
        "NotFound" => error.call("No such record, or the resource is not served (`not_found`)."),
        "ShowOk" => success("The show page's layout", schema_ref("ShowResponse"), degraded: true),
        "FormOk" => success("The form, as the client renders it", schema_ref("FormResponse"), degraded: true),
        "Created" => success("Created", schema_ref("WriteResult")),
        "Written" => success("The write was applied", schema_ref("WriteResult")),
        "MetaOk" => success("Resource metadata", schema_ref("ResourceMeta")),
        "OptionsOk" => success("Matching options", schema_ref("OptionsResponse")),
        "LookupOk" => success("Options per requested field", schema_ref("LookupResponse")),
        "LabelsOk" => success("Labels of the readable records", schema_ref("LabelsResponse")),
        "ValueOk" => success("The full value", schema_ref("ValueResponse"))
      }.freeze
    end
  end
end
