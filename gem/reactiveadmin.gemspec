require_relative "lib/reactive_admin/version"

Gem::Specification.new do |s|
  s.name = "reactiveadmin"
  s.version = ReactiveAdmin::VERSION
  s.summary = "Serve ActiveAdmin registrations as a JSON API"
  s.description = "Reuses your ActiveAdmin registrations and controllers to serve a JSON API, an OpenAPI document and an MCP server, and to host a React admin client."
  s.authors = ["reactiveadmin contributors"]
  s.license = "MIT"
  s.homepage = "https://github.com/formhealth/reactiveadmin"
  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "changelog_uri" => "#{s.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{s.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }
  s.required_ruby_version = ">= 3.4"
  s.files = Dir["{app,lib}/**/*"]
  # AA_PROBE lifts the cap for the aa4 probe job (gemfiles/aa4.gemfile); never set it in an app.
  s.add_dependency "activeadmin", ">= 3.5", (ENV["AA_PROBE"] ? "< 5" : "< 4")
  s.add_dependency "rails", ">= 7.2"
  s.add_dependency "nokogiri"
end
