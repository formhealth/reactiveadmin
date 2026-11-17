module ApiHelpers
  JSON_HEADERS = {"ACCEPT" => "application/json", "CONTENT_TYPE" => "application/json"}.freeze
  # A nested index (`/admin/authors/1/posts`) fits this template too.
  MEMBER_ACTION = "/admin/{resource}/{id}/{action}"

  def sign_in(user) = post("/test/sign_in", params: {id: user.id})

  def json = response.parsed_body

  # Sends a request the way the client does and enforces what must hold for every response: the
  # body is JSON (never an html page), errors match the contract, and a success matches `schema`, or
  # else whatever core.yaml declares for the verb, path and status. `schema: false` is for a host's own JSON.
  def api(verb, path, body = nil, schema: nil, headers: {}, params: nil)
    headers = JSON_HEADERS.merge(headers)
    payload = body && (body.is_a?(String) ? body : body.to_json)
    send(verb, path, params: payload || params, headers:)
    check_contract(schema)
    response.parsed_body if json_response?
  end

  def api_get(path, params = nil, schema: nil, headers: {}, **query) = api(:get, path, nil, schema:, headers:, params: (params || {}).merge(query))

  # The token the edit form hands out; updates must send it back as `lock`.
  def lock_of(record)
    config = ReactiveAdmin::Registry.for_class(record.class)
    api_get("#{ReactiveAdmin::Paths.api(ReactiveAdmin::Paths.member(config, record))}/edit")["lock"]
  end

  def csrf_token = api_get("/api/admin/_session")["csrf_token"]

  # The `_value` token the server would sign for `user`; the page that issues it isn't rendered.
  def value_token(record, field, user:, via: "show")
    config = ReactiveAdmin::Registry.for_class(record.class)
    controller = Object.new.tap { it.instance_variable_set(:@reactiveadmin_token_user, user.id.to_s) }
    ReactiveAdmin::ValueToken.mint(controller, config, record, field, via)
  end

  def json_response? = response.media_type == "application/json"

  def check_contract(schema)
    return if response.media_type == "text/csv" && response.successful?

    expect(response.media_type).to eq("application/json"), "expected JSON, got #{response.media_type} (#{response.status})"
    return unless response.parsed_body

    schema = if response.status >= 400
      (response.status == 422 && json.key?("errors")) ? "ValidationError" : "Error"
    else
      schema.nil? ? inferred_schema : schema
    end
    expect(json).to match_contract(schema) if schema
  end

  # Custom actions are served at paths core.yaml can't tell from a record's or an index's, so they are matched by
  # what the controller ran.
  def inferred_schema
    status = response.status
    case served_as
    when :page then Contract.operation_schema("getPage", status)
    when :action then Contract.operation_schema("runMemberAction#{request.request_method.capitalize}", status)
    else Contract.response_schema(request.request_method, request.path, status) unless Contract.template(request.path) == MEMBER_ACTION
    end
  end

  def served_as
    name = controller.action_name
    case controller
    when ActiveAdmin::PageController then %w[index reactiveadmin_page].include?(name) ? :page : :action
    when ActiveAdmin::ResourceController then :action unless %w[index show new edit create update destroy batch_action].include?(name) || name.start_with?("reactiveadmin_")
    end
  end

  def row_for(rows, record) = rows.find { it["id"] == record.id.to_s }

  def by_key(list, key = "key") = list.index_by { it[key] }

  def fields_of(form) = form["sections"].flat_map { it["fields"] || [] }.index_by { it["name"] }

  # Every node of `type` anywhere in a layout, including table cells and attribute rows.
  def nodes_of(tree, type)
    Array.wrap(tree).flat_map do |node|
      next [] unless node.is_a?(Hash)

      nested = [node["children"], node["rows"]&.flatten, (node["value"] if node["value"].is_a?(Array)), node["action"]].compact
      ((node["type"] == type) ? [node] : []) + nested.flat_map { nodes_of(it, type) }
    end
  end
end
