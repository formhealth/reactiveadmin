RSpec.describe ReactiveAdmin::OpenApi do
  include_context "with a blog"

  let(:doc) { described_class.build(admin) }
  let(:operations) { doc["paths"].flat_map { |path, item| item.map { |verb, operation| [verb, path, operation] } } }

  def operation_ids(document) = document["paths"].values.flat_map { |item| item.values.pluck("operationId") }

  def refs(node)
    case node
    when Hash then node.flat_map { |key, value| (key == "$ref") ? [value] : refs(value) }
    when Array then node.flat_map { refs(it) }
    else []
    end
  end

  def resolve(document, ref) = ref.delete_prefix("#/").split("/").inject(document) { |node, key| node&.fetch(key, nil) }

  def op(document, verb, path) = document.dig("paths", path, verb)

  describe "the document" do
    it "is OpenAPI 3.1 with info from config, a root server and the mount prefix on every path" do
      expect(doc).to include("openapi" => "3.1.0", "info" => {"title" => "Admin API", "version" => ReactiveAdmin::VERSION}, "servers" => [{"url" => "/"}])
      expect(doc["paths"].keys).to all(start_with("/api/admin/"))
    end

    it "takes info overrides from the configuration" do
      settings = ReactiveAdmin.config.openapi
      old = settings.info
      settings.info = {title: "Acme Admin API", version: "7", description: "Internal"}

      expect(doc["info"]).to eq("title" => "Acme Admin API", "version" => "7", "description" => "Internal")
    ensure
      settings.info = old
    end

    it "validates against the OpenAPI 3.1 meta-schema" do
      errors = JSONSchemer.openapi(JSON.parse(doc.to_json)).validate.map { it["error"] }

      expect(errors).to eq([])
    end

    it "validates in full mode too" do
      errors = JSONSchemer.openapi(JSON.parse(described_class.build(full: true).to_json)).validate.map { it["error"] }

      expect(errors).to eq([])
    end

    it "resolves every $ref" do
      unresolved = refs(doc).uniq.reject { resolve(doc, it) }

      expect(unresolved).to eq([])
    end

    it "embeds only the core schemas its paths reach, as 3.1 JSON Schema" do
      schemas = doc.dig("components", "schemas")

      expect(schemas.keys).to include("Node", "IndexResponse", "FormResponse", "Error")
      expect(schemas.keys).not_to include("RecordParams", "BatchActionRequest")
      expect(doc.dig("components", "parameters").keys).not_to include("Resource")
      expect(JSON.generate(doc)).not_to match(/"nullable"|"example":/)
      expect(schemas.dig("Error", "properties", "location", "type")).to eq(%w[string null])
    end

    it "gives every operation a unique id, a security requirement and the standard errors" do
      ids = operation_ids(doc)

      expect(ids).to eq(ids.uniq)
      expect(operations.reject { |_, path, _| path.end_with?("/_mcp") }.map { |_, _, operation| operation["responses"].keys }).to all(include("401", "429"))
    end

    it "names operations after what they do" do
      expect(operation_ids(doc)).to include("listPosts", "getPost", "createPost", "updatePost", "getNewPostForm", "getEditPostForm", "getPostsMeta",
        "getPostsOptions", "getPostValue", "batchPosts", "exportPostsCsv", "postPublish", "postsStats", "getManifest", "getSession", "getOpenApi")
    end

    it "is deterministic" do
      expect(described_class.build(admin)).to eq(doc)
      expect(described_class.build(admin).to_json).to eq(doc.to_json)
    end

    it "orders tags and tag groups by the admin's menu" do
      groups = doc["x-tagGroups"].to_h { [it["name"], it["tags"]] }

      expect(groups["Content"]).to eq(%w[posts tags authors])
      expect(groups.values.flatten).to match_array(doc["tags"].pluck("name"))
      expect(doc["tags"].pluck("name")).to include("posts", "page:dashboard", "meta")
    end

    it "serializes to YAML that loads back to the same document" do
      expect(YAML.safe_load(described_class.to_yaml(doc))).to eq(doc)
    end
  end

  describe "security" do
    it "documents the session cookie and the CSRF header, which only writes need" do
      schemes = doc.dig("components", "securitySchemes")

      expect(schemes["sessionCookie"]).to include("type" => "apiKey", "in" => "cookie")
      expect(schemes["csrfToken"]).to include("type" => "apiKey", "in" => "header", "name" => "X-CSRF-Token")
      expect(doc["security"]).to eq([{"sessionCookie" => []}, {"bearerAuth" => []}])
      expect(op(doc, "get", "/api/admin/posts")["security"]).to be_nil
      expect(op(doc, "post", "/api/admin/posts")["security"]).to eq([{"sessionCookie" => [], "csrfToken" => []}, {"bearerAuth" => []}])
    end

    it "declares the bearer token, and the MCP endpoint that takes only it, where a bearer adapter is configured" do
      expect(doc.dig("components", "securitySchemes", "bearerAuth")).to include("type" => "http", "scheme" => "bearer")
      mcp = op(doc, "post", "/api/admin/_mcp")

      expect(mcp).to include("operationId" => "postMcp", "security" => [{"bearerAuth" => []}], "tags" => ["meta"])
      expect(doc.dig("components", "schemas")).to include("McpRequest", "McpResponse")
    end

    it "leaves out the bearer token and the MCP endpoint without a bearer adapter" do
      allow(ReactiveAdmin.config).to receive(:auth).and_return(nil)

      expect(doc.dig("components", "securitySchemes").keys).to match_array(%w[csrfToken sessionCookie])
      expect(doc["paths"]).not_to have_key("/api/admin/_mcp")
      expect(doc["security"]).to eq([{"sessionCookie" => []}])
    end

    it "leaves out the MCP endpoint where MCP is off for the user" do
      allow(ReactiveAdmin.config.mcp).to receive(:enabled).and_return(->(user) { user != admin })

      expect(doc["paths"]).not_to have_key("/api/admin/_mcp")
      expect(described_class.build(editor)["paths"]).to have_key("/api/admin/_mcp")
      expect(doc.dig("components", "securitySchemes")).to have_key("bearerAuth")
    end

    it "follows configured schemes, such as a bearer token" do
      settings = ReactiveAdmin.config.openapi
      settings.security_schemes = {bearer: {type: "http", scheme: "bearer"}}

      expect(doc.dig("components", "securitySchemes")).to eq("bearer" => {"type" => "http", "scheme" => "bearer"})
      expect(doc["security"]).to eq([{"bearer" => []}])
      expect(op(doc, "post", "/api/admin/posts")["security"]).to eq([{"bearer" => []}])
    ensure
      settings.security_schemes = nil
    end
  end

  describe "what a resource exposes" do
    it "types the list's query from the declared filters, scopes, sort keys and page size" do
      parameters = op(doc, "get", "/api/admin/posts")["parameters"].index_by { it["name"] }
      filters = parameters.dig("q", "schema", "properties")

      expect(parameters["q"]).to include("style" => "deepObject", "explode" => true)
      expect(filters.keys).to include("title_cont", "views_count_gt", "published_at_gteq", "featured_eq", "category_id_in")
      expect(filters["views_count_gt"]["type"]).to eq("number")
      expect(filters["featured_eq"]["type"]).to eq("boolean")
      expect(filters["published_at_gteq"]).to include("type" => "string", "format" => "date")
      expect(filters["category_id_in"]).to include("type" => "array")
      expect(parameters["scope"]["schema"]["enum"]).to include("all", "draft", "published", "archived")
      expect(parameters["order"]["schema"]["enum"]).to include("title_asc", "published_at_desc", "views_count_desc")
      expect(parameters["per_page"]["schema"]).to include("maximum" => ReactiveAdmin.config.max_per_page)
    end

    it "offers only the declared filters, never a column the resource doesn't filter on" do
      filters = op(doc, "get", "/api/admin/posts")["parameters"].find { it["name"] == "q" }.dig("schema", "properties")

      expect(filters.keys.grep(/\A(body|metadata)_/)).to eq([])
      expect(filters.keys.grep(/\Atitle_/)).to include("title_cont")
    end

    it "builds the write body from the controls-only form, with nested rows and the lock" do
      create = doc.dig("components", "schemas", "PostCreateParams")
      post = create.dig("properties", "post")

      expect(create["required"]).to eq(%w[post])
      expect(post["properties"].keys).to include("title", "status", "author_id", "featured", "published_at", "metadata", "tag_ids", "comments_attributes")
      expect(post["properties"]["featured"]).to eq("type" => "boolean")
      expect(post["properties"]["tag_ids"]).to include("type" => "array")
      expect(post["properties"]["comments_attributes"]["additionalProperties"]["properties"].keys).to include("body", "approved", "id", "_destroy")
      expect(doc.dig("components", "schemas", "PostUpdateParams", "properties", "lock")).to eq("$ref" => "#/components/schemas/FormLock")
    end

    it "types row cells by their attribute where the column is an attribute" do
      cells = doc.dig("components", "schemas", "PostRow", "allOf", 1, "properties", "cells", "properties")

      expect(cells["published_at"]["allOf"].last.dig("properties", "type", "enum")).to include("datetime")
      expect(cells["title"]["allOf"].last.dig("properties", "type", "enum")).to include("text")
      expect(cells["link"]).to include("$ref" => "#/components/schemas/Node")
    end

    it "describes batch actions with their typed inputs" do
      schemas = op(doc, "post", "/api/admin/posts/batch_action").dig("requestBody", "content", "application/json", "schema", "oneOf")
      set_status = schemas.find { it.dig("properties", "batch_action", "const") == "set_status" }

      expect(schemas.map { it.dig("properties", "batch_action", "const") }).to include("set_status", "feature")
      expect(schemas.map { it.dig("properties", "batch_action", "const") }.include?("destroy")).to eq(can_destroy_post?(admin))
      expect(set_status.dig("properties", "batch_action_inputs", "properties").keys).to eq(%w[status note])
    end

    it "documents custom member and collection actions by verb" do
      expect(op(doc, "put", "/api/admin/posts/{id}/publish")).to include("operationId" => "postPublish")
      expect(op(doc, "get", "/api/admin/posts/{id}/rename")["operationId"]).to eq("postRenameGet")
      expect(op(doc, "post", "/api/admin/posts/{id}/rename")["operationId"]).to eq("postRenamePost")
      expect(op(doc, "post", "/api/admin/posts/import")).to include("operationId" => "postsImport")
    end

    it "documents nested resources under their parent" do
      expect(op(doc, "get", "/api/admin/posts/{post_id}/comments")["parameters"]).to include(include("name" => "post_id", "in" => "path"))
      expect(op(doc, "get", "/api/admin/comments/_meta")).to include("operationId" => "getCommentsMeta")
      expect(doc["paths"]).not_to have_key("/api/admin/comments")
    end

    it "documents pages and their page actions" do
      expect(op(doc, "get", "/api/admin/_pages/dashboard")).to include("operationId" => "getDashboardPage")
      expect(op(doc, "post", "/api/admin/dashboard/recalc")).to include("operationId" => "dashboardRecalc")
    end

    it "documents the fields of a GET form as free-form query parameters of its view's operation" do
      page = op(doc, "get", "/api/admin/_pages/ticket_report")
      action = op(doc, "get", "/api/admin/tickets/{id}/related")

      [page, action].each do |operation|
        expect(operation["parameters"]).to include(include("name" => "form_fields", "in" => "query", "style" => "form", "explode" => true))
      end
      expect(op(doc, "get", "/api/admin/tickets/{id}/lookup")["parameters"].pluck("name")).not_to include("form_fields")
      expect(op(doc, "get", "/api/admin/_pages/dashboard")["parameters"].to_a.pluck("name")).not_to include("form_fields")
    end

    it "leaves the csv export out of a resource that offers none" do
      expect(doc["paths"]).to have_key("/api/admin/posts.csv")
      expect(doc["paths"]).not_to have_key("/api/admin/tags.csv")
    end

    it "documents the metadata endpoints" do
      expect(op(doc, "get", "/api/admin/_manifest")["operationId"]).to eq("getManifest")
      expect(op(doc, "get", "/api/admin/_session")["operationId"]).to eq("getSession")
      expect(op(doc, "get", "/api/admin/_openapi")["operationId"]).to eq("getOpenApi")
    end
  end

  describe "what it leaves out" do
    it "carries no record data, and no option values drawn from the database" do
      text = JSON.generate(doc)

      ["Hello world", "Bob's draft", "alice@example.com", "Alice Author", "Bob Builder", "News", "ruby", "hello"].each do |value|
        expect(text).not_to include(%("#{value}")), value
      end
      expect(doc.dig("components", "schemas", "PostRow").to_json).not_to include("Hello")
      expect(op(doc, "get", "/api/admin/posts")["parameters"].find { it["name"] == "q" }.to_json).not_to match(/"enum"/)
    end

    it "omits masked attributes from filters, rows and write bodies" do
      Category.create!(name: "Secret", api_token: "tok-123")
      text = JSON.generate(doc)

      expect(text).not_to include("api_token", "tok-123")
      expect(doc.dig("components", "schemas", "CategoryCreateParams", "properties", "category", "properties").keys).to eq(%w[name settings])
    end

    it "omits columns that secure defaults hide" do
      cells = doc.dig("components", "schemas", "ScanRow", "allOf", 1, "properties", "cells", "properties")

      expect(cells.keys).to include("title")
      expect(cells.keys).not_to include("image")
    end

    it "omits resources and pages that expose = :listed doesn't name" do
      ReactiveAdmin::MenuOverlay.reset!
      ReactiveAdmin.config.expose = :listed
      ReactiveAdmin.menu { group("Content") { resources :posts } }

      listed = described_class.build(admin)

      expect(listed["tags"].pluck("name")).to include("posts", "meta")
      expect(listed["tags"].pluck("name")).not_to include("categories", "tickets", "authors")
      expect(listed["paths"].keys.grep(%r{/admin/(categories|tickets|authors)})).to eq([])
    ensure
      ReactiveAdmin.config.expose = :all
      ReactiveAdmin::Registry.resources.each { it.reactive_options.delete(:expose) }
      ReactiveAdmin::MenuOverlay.reset!
    end

    it "leaves a resource whose form can't be built with a generic body, and says so" do
      allow(ReactiveAdmin::FormSchema).to receive(:new).and_raise(RuntimeError, "boom")

      expect(doc.dig("components", "schemas", "PostCreateParams", "additionalProperties")).to eq("type" => "object", "additionalProperties" => true)
      expect(JSON.generate(doc)).not_to include("boom")
    end
  end

  describe "authorization" do
    let(:editor_doc) { described_class.build(editor) }

    it "gives users with different permissions different documents" do
      expect(editor_doc).not_to eq(doc)
      expect(op(doc, "get", "/api/admin/posts")["parameters"].find { it["name"] == "scope" }.dig("schema", "enum")).to include("featured")
      expect(op(editor_doc, "get", "/api/admin/posts")["parameters"].find { it["name"] == "scope" }.dig("schema", "enum")).not_to include("featured")
      expect(op(doc, "post", "/api/admin/posts/batch_action").to_json).to include("admins_only")
      expect(op(editor_doc, "post", "/api/admin/posts/batch_action").to_json).not_to include("admins_only")
    end

    it "includes only the operations the adapter lets the user take" do
      [[admin, doc], [editor, editor_doc]].each do |user, document|
        expect(op(document, "delete", "/api/admin/posts/{id}").present?).to eq(can_destroy_post?(user))
        expect(op(document, "post", "/api/admin/posts/import").present?).to eq(can_import_posts?(user))
        expect(document["paths"].key?("/api/admin/categories")).to eq(can_read_categories?(user))
      end
    end

    it "describes the whole exposed surface in full mode, and never less than any user sees" do
      full = described_class.build(full: true)

      expect(operation_ids(full)).to include(*operation_ids(doc), *operation_ids(editor_doc))
      expect(full["paths"]).to have_key("/api/admin/categories")
      expect(op(full, "delete", "/api/admin/posts/{id}")).to be_present
    end

    it "is cached by who is asking, not shared between users" do
      controller = Struct.new(:request).new(ActionDispatch::Request.new(Rack::MockRequest.env_for("/api/admin/_openapi")))
      allow(ReactiveAdmin).to receive_messages(user_fingerprint: "a", current_user: admin)
      allow(described_class).to receive(:build).and_return({"built" => 1})

      described_class.fetch(controller)
      described_class.fetch(controller)
      allow(ReactiveAdmin).to receive(:user_fingerprint).and_return("b")
      described_class.fetch(controller)

      expect(described_class).to have_received(:build).twice
    end

    it "is cached apart for a session and a token, which the api guards treat differently" do
      request = ->(headers = {}) { Struct.new(:request).new(ActionDispatch::Request.new(Rack::MockRequest.env_for("/api/admin/_openapi", headers))) }
      allow(ReactiveAdmin).to receive_messages(user_fingerprint: "a", current_user: admin)
      allow(described_class).to receive(:build).and_return({"built" => 1})

      described_class.fetch(request.call)
      described_class.fetch(request.call("HTTP_AUTHORIZATION" => "Bearer abc"))

      expect(described_class).to have_received(:build).with(admin, hash_including(channel: :session))
      expect(described_class).to have_received(:build).with(admin, hash_including(channel: :token))
    end
  end
end
