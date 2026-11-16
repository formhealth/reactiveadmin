# Boots the dummy app against the gem as installed from a built .gem (BUNDLE_GEMFILE points at a Gemfile with no
# path to this checkout) and checks what a host with no Node toolchain gets: the manifest and the client's page.
# Usage: BUNDLE_GEMFILE=<scratch Gemfile> ruby script/smoke_packaged_gem.rb
ENV["RAILS_ENV"] = "test"
require_relative "../spec/dummy/config/environment"
require "action_dispatch/testing/integration"

Rails.application.reload_routes_unless_loaded
ActiveRecord::Migration.suppress_messages { load File.expand_path("../spec/dummy/db/schema.rb", __dir__) }

failures = 0
check = lambda do |ok, message|
  puts "#{ok ? "ok  " : "FAIL"} #{message}"
  failures += 1 unless ok
end

gem_dir = Gem.loaded_specs.fetch("reactiveadmin").full_gem_path
check.call(!gem_dir.start_with?(File.expand_path("..", __dir__)), "reactiveadmin loads from an installed gem (#{gem_dir})")
check.call(%w[README.md LICENSE CHANGELOG.md].all? { File.file?(File.join(gem_dir, it)) }, "the README, LICENSE and CHANGELOG ship")
check.call(ReactiveAdmin::Ui::Assets.root.to_s == File.join(gem_dir, "vendor/client"), "the packaged client is served")

token = DummyTokens.issue(AdminUser.create!(name: "Ada Admin", email: "ada@example.com", role: "admin"))
http = ActionDispatch::Integration::Session.new(Rails.application)

http.get "/api/admin/_manifest", headers: {"Authorization" => "Bearer #{token}", "Accept" => "application/json"}
manifest = http.response.parsed_body
check.call(http.response.status == 200 && manifest["schema_version"] == ReactiveAdmin::Manifest::SCHEMA_VERSION, "GET /api/admin/_manifest answers with schema_version #{ReactiveAdmin::Manifest::SCHEMA_VERSION}")

page = {"Cookie" => "reactiveadmin_ui=new", "Sec-Fetch-Dest" => "document", "Accept" => "text/html"}
http.get "/admin", headers: page
check.call(!http.response.body.include?('<div id="root">'), "GET /admin stays classic until the host sets ui.available")

ReactiveAdmin.config.ui.available = ->(_user) { true }
http.get "/admin", headers: page
html = http.response.body
check.call(http.response.status == 200 && html.include?('<div id="root">'), "GET /admin with the new-UI cookie answers with the client's page")

script = html[/<script type="module" src="([^"]+)"/, 1]
prefix = ReactiveAdmin::Ui::Assets.prefix
check.call(script&.start_with?("#{prefix}/assets/"), "the page loads #{script}")
http.get script.to_s
entry = http.response.body
check.call(http.response.status == 200 && entry.size > 1_000, "the entry script is served from the gem")

# The build refers to its chunks relatively, so they load from wherever the entry did.
chunk = entry[%r{(?:import|from)\s*["']\./([\w.-]+\.js)["']}, 1]
http.get "#{prefix}/assets/#{chunk}"
check.call(chunk && http.response.status == 200, "a chunk the entry imports (#{chunk}) is served under #{prefix}")
check.call(!entry.include?('"/reactiveadmin/assets/') || prefix == "/reactiveadmin", "the entry names no other prefix")

exit 1 if failures.positive?
