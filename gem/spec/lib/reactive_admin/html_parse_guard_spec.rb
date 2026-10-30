require "rails_helper"

# Markup is parsed through HtmlPolicy, which caps depth, nodes and bytes. A direct parse can raise on deep
# markup or run unbounded, so each one elsewhere needs a reason here.
RSpec.describe "Direct HTML parsing" do
  let(:lib) { File.expand_path("../../../lib", __dir__) }
  let(:pattern) { /Nokogiri::HTML\d*\b|\.fragment\(/ }
  let(:allowlist) do
    {
      "reactive_admin/frame.rb" => "Parses a whole classic page to find its content; rescues the depth error and " \
        "hands the result to HtmlPolicy.frame_body, which caps it."
    }
  end

  it "parses html only through HtmlPolicy or an allowlisted site" do
    offenders = Dir[File.join(lib, "**/*.rb")].sort.flat_map do |file|
      relative = file.delete_prefix("#{lib}/")
      next [] if relative == "reactive_admin/html_policy.rb" || allowlist.key?(relative)

      File.readlines(file).each_with_index.filter_map do |line, index|
        next if line.lstrip.start_with?("#") || !line.match?(pattern)

        "lib/#{relative}:#{index + 1}: #{line.strip}"
      end
    end

    expect(offenders).to eq []
  end

  it "allowlists only files that still parse directly" do
    stale = allowlist.keys.reject { File.read(File.join(lib, it)).match?(pattern) }

    expect(stale).to eq []
  end
end
