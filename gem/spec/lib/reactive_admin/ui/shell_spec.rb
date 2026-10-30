RSpec.describe ReactiveAdmin::Ui::Shell do
  around { |example| with_ui { example.run } }

  let(:inner) { ->(_env) { [200, {"content-type" => "text/plain"}, ["classic"]] } }
  let(:headers) { {"HTTP_COOKIE" => "reactiveadmin_ui=new", "HTTP_SEC_FETCH_DEST" => "document"} }

  # Rack::Lint is what a real server enforces, and request specs don't.
  def get(env = {}, path = "/admin/posts") = Rack::MockRequest.new(Rack::Lint.new(described_class.new(inner))).get(path, headers.merge(env))

  it "carries the request's nonce, when the host's policy generates one" do
    response = get("action_dispatch.content_security_policy_nonce_generator" => ->(_request) { "n0nce" })

    expect(response.body).to include('src="/reactiveadmin/assets/index-abc123.js" nonce="n0nce"')
  end

  it "has no nonce attribute without a generator" do
    expect(get.body).to include('src="/reactiveadmin/assets/index-abc123.js"></script>')
  end

  it "answers with headers a Rack server accepts, the host's defaults included" do
    response = get

    expect(response.status).to eq(200)
    expect(response.headers).to include("cache-control" => "no-store", "x-frame-options" => "SAMEORIGIN")
  end

  it "serves the shell for a record id that contains a dot" do
    expect(get({}, "/admin/users/john.doe").body).to include("reactiveadmin-config")
  end

  %w[csv json xml].each do |format|
    it "passes a .#{format} download through to the app" do
      expect(get({}, "/admin/authors.#{format}").body).to eq("classic")
    end
  end

  it "passes everything else to the app untouched" do
    expect(get("HTTP_COOKIE" => "").body).to eq("classic")
  end
end
