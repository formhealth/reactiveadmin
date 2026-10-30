RSpec.describe "controls-only form schema", type: :request do
  include_context "with a blog"

  # What write guards and param normalization read from a schema. A single select and a typeahead are
  # normalized alike, so options that truncate into a typeahead are not a difference.
  def decisions(schema)
    {
      submittable: schema.submittable?,
      unsupported: schema.unsupported_kinds.sort,
      nested: schema.nested_associations.map(&:to_s).sort,
      fields: schema.sections.flat_map { guarded_fields(it) }.map do |field|
        [field[:param], (field[:control] == "typeahead") ? "select" : field[:control], !!field[:disabled], !!field[:summary], !!field[:masked]]
      end
    }
  end

  def guarded_fields(section)
    fields = (section[:kind] == "has_many") ? [*section[:records].to_a.flat_map { it[:fields] }, *section[:template_fields]] : section[:fields].to_a
    fields.select { it[:param] }
  end

  # Builds the other flavour of every schema the request builds and keeps both sets of decisions.
  def compare_schemas
    pairs = []
    allow(ReactiveAdmin::FormSchema).to receive(:new).and_wrap_original do |original, controller, record, **options|
      schema = original.call(controller, record, **options)
      twin = original.call(controller, record, **options, controls_only: !options[:controls_only])
      full, light = options[:controls_only] ? [twin, schema] : [schema, twin]
      pairs << [decisions(full), decisions(light)]
      schema
    end
    yield
    pairs
  end

  def forms_of(config)
    parent = ReactiveAdmin::Paths.nested?(config) ? config.belongs_to_config.target.resource_class.first : nil
    collection = ReactiveAdmin::Paths.api(ReactiveAdmin::Paths.collection(config, parent_id: parent&.to_param))
    record = config.resource_class.first
    ["#{collection}/new", *("#{collection}/#{ERB::Util.url_encode(record.to_param)}/edit" if record)]
  end

  def visit_every_form
    ReactiveAdmin::Registry.resources.flat_map { |config| forms_of(config) }.each { get it, headers: ApiHelpers::JSON_HEADERS }
  end

  before do
    Comment.create!(post: first_post, body: "Nice", context: {"api_token" => "t", "a" => 1})
    Memo.create!(title: "Memo", payload: {"a" => 1})
    Tag.create!(name: "rails")
  end

  {"admin" => :admin, "editor" => :editor}.each do |role, user|
    {"default limits" => {}, "options truncated" => {inline_options_limit: 1}, "json summarized" => {inline_json_limit: 4}}.each do |name, settings|
      it "makes the same guard decisions as the full schema on every form (#{role}, #{name})" do
        old = settings.to_h { |key, _| [key, ReactiveAdmin.config.public_send(key)] }
        settings.each { |key, value| ReactiveAdmin.config.public_send(:"#{key}=", value) }
        sign_in public_send(user)

        pairs = compare_schemas { visit_every_form }

        expect(pairs.size).to be >= 10
        pairs.each { |full, light| expect(light).to eq(full) }
        expect(pairs.flat_map { it.first[:fields] }.map { it[1] }.uniq).to include("text", "select", "json", "boolean")
      ensure
        old.each { |key, value| ReactiveAdmin.config.public_send(:"#{key}=", value) }
      end
    end
  end

  it "makes the same decisions on a write, where the controls-only schema is the one built" do
    sign_in admin
    pairs = compare_schemas do
      api(:patch, "/api/admin/posts/#{first_post.id}", {post: {title: "Renamed"}, lock: lock_of(first_post)})
    end

    expect(response).to have_http_status(:ok)
    expect(pairs).not_to be_empty
    pairs.each { |full, light| expect(light).to eq(full) }
  end

  it "records neither options, labels nor html" do
    sign_in admin
    built = []
    allow(ReactiveAdmin::FormSchema).to receive(:new).and_wrap_original do |original, *args, **options|
      original.call(*args, **options).tap { built << it if options[:controls_only] }
    end

    api(:patch, "/api/admin/posts/#{first_post.id}", {post: {title: "Renamed"}, lock: lock_of(first_post)})

    fields = built.flat_map { |schema| schema.sections.flat_map { it[:fields].to_a } }
    expect(fields).not_to be_empty
    expect(fields.flat_map(&:keys).uniq - %i[name param control disabled masked summary]).to be_empty
  end
end
