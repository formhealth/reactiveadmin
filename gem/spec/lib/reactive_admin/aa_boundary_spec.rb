require "rails_helper"

# Every ActiveAdmin, Arbre, Formtastic and inherited_resources internal goes through ReactiveAdmin::AA, so
# an AA upgrade touches `aa.rb` and `aa/` only. See the module comment in lib/reactive_admin/aa.rb for
# what is deliberately left outside (the read-only config API, hook names, the host DSL).
module AaBoundary
  GEM_ROOT = File.expand_path("../../..", __dir__)

  INTERNALS = [
    /\bActiveAdmin(::|\.[a-z_])/,
    /\bArbre::/,
    /\bFormtastic::/,
    /InheritedResources/,
    /\b(get|set)_resource_ivar\b|@resource_params\b/,
    /send\(:(active_admin_config|resource|build_resource|collection|collection_before_scope|current_scope|scope_chain|apply_decorations|authorize_resource!|find_resource|scoped_collection)\b/
  ].freeze

  # path (relative to gem/) => why code outside the adapter may name AA internals. Empty on purpose: add an
  # entry only for a documented integration surface, with the reason.
  ALLOWLIST = {}.freeze

  module_function

  def internal?(line) = !line.lstrip.start_with?("#") && INTERNALS.any? { line.match?(it) }

  def inside?(path) = path == "lib/reactive_admin/aa.rb" || path.start_with?("lib/reactive_admin/aa/")

  def violations
    Dir[File.join(GEM_ROOT, "{lib,app}/**/*")].select { File.file?(it) }.sort.flat_map do |file|
      path = file.delete_prefix("#{GEM_ROOT}/")
      next [] if inside?(path) || ALLOWLIST.key?(path)

      File.readlines(file).each_with_index.filter_map { |line, index| "#{path}:#{index + 1}: #{line.strip}" if internal?(line) }
    end
  end
end

RSpec.describe "the ReactiveAdmin::AA boundary" do
  it "keeps AA internals out of lib and app, outside aa.rb and aa/" do
    found = AaBoundary.violations
    expect(found).to be_empty, "AA internals outside ReactiveAdmin::AA:\n#{found.join("\n")}"
  end

  it "has no stale allowlist entries" do
    AaBoundary::ALLOWLIST.each_key do |path|
      expect(File.readlines(File.join(AaBoundary::GEM_ROOT, path)).any? { AaBoundary.internal?(it) }).to be(true), "#{path} no longer needs its allowlist entry"
    end
  end

  it "recognizes internals and skips comments" do
    ["x = ActiveAdmin::Resource", "ActiveAdmin.application", "Arbre::Element", "Formtastic::Inputs", "c.send(:get_resource_ivar)", "@controller.send(:collection)"].each do |line|
      expect(AaBoundary.internal?(line)).to be(true), line
    end
    ["AA.page?(config)", "  # ActiveAdmin::Page in a comment"].each { |line| expect(AaBoundary.internal?(line)).to be(false), line }
  end
end
