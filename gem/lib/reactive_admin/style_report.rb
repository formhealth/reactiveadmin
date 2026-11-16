require "json"

module ReactiveAdmin
  # Where the host's markup uses classes and inline styles the walker has no typed layout for, with
  # the exact strings, the source lines and what to use instead. Two views of the same problem:
  # `sampled` is what the API degrades on for the sampled records (grouped by resource), and
  # `scanned` is every style and utility class in the host's admin source, whether or not a sample
  # reached it. Output names resources, files and CSS strings only, never record data.
  class StyleReport
    KINDS = %w[unknown_layout_class inline_style_ignored].freeze
    SCAN = %w[app/admin/**/* app/views/admin/**/*].freeze
    STYLE_ATTRIBUTE = /\bstyle(?:=|:\s*|\s*=>\s*)(?:"([^"]*)"|'([^']*)')/
    CLASS_ATTRIBUTE = /\bclass(?:=|:\s*|\s*=>\s*)(?:"([^"]*)"|'([^']*)')/

    Finding = Data.define(:resource, :kind, :value, :untranslated, :count, :paths, :sources, :advice)
    Occurrence = Data.define(:file, :line, :kind, :value, :untranslated, :advice)

    def self.run(**) = new(**).run

    def initialize(user: nil, sample: true)
      @user = user
      @sample = sample
    end

    def run
      Rails.application.reload_routes_unless_loaded
      entries = StyleSources.trace { Doctor.run(user: @user, sample: @sample)[:diagnostics] }
      {sampled: sampled(entries), scanned: scanned}
    end

    private

    def sampled(entries)
      entries.select { KINDS.include?(it[:kind]) }.group_by { [it[:resource].presence || "(unlabelled)", it[:kind], it[:class] || it[:style]] }.map do |(resource, kind, value), group|
        untranslated = (kind == "inline_style_ignored") ? group.first[:ignored] : value
        Finding.new(resource:, kind:, value:, untranslated:, count: group.size, paths: group.pluck(:path).first(3),
          sources: group.filter_map { it[:source] }.flat_map { it.split(", ") }.uniq, advice: advice(kind, untranslated))
      end.sort_by { [it.resource, it.kind, it.value] }
    end

    def scanned
      Rails.root.glob(SCAN).sort.select(&:file?).flat_map { |path| occurrences(path) }
    end

    def occurrences(path)
      file = path.relative_path_from(Rails.root).to_s
      path.each_line.with_index(1).flat_map do |text, line|
        text = text.scrub
        [*strings(text, STYLE_ATTRIBUTE).filter_map { occurrence(file, line, "inline_style_ignored", it) },
          *strings(text, CLASS_ATTRIBUTE).filter_map { occurrence(file, line, "unknown_layout_class", it) }]
      end
    end

    def strings(text, pattern) = text.scan(pattern).map { it.compact.first }.reject { it.include?("\#{") }

    # Only what the walker can't translate fully is a finding; `value` keeps the exact string.
    def occurrence(file, line, kind, value)
      untranslated = (kind == "inline_style_ignored") ? InlineStyle.parse(value).unknown.join("; ") : LayoutClasses.parse(value).unknown.join(" ")
      Occurrence.new(file:, line:, kind:, value:, untranslated:, advice: advice(kind, untranslated)) if untranslated.present?
    end

    def advice(kind, untranslated)
      if kind == "inline_style_ignored"
        untranslated.split("; ").map { "#{it.split(":").first}: #{InlineStyle.advice(it)}" }.uniq.join("; ")
      else
        untranslated.split.map { "#{it}: #{LayoutClasses.advice(it)}" }.join("; ")
      end
    end

    # Markdown and JSON renderings.
    class Renderer
      def initialize(report) = @report = report

      def to_json(*) = JSON.pretty_generate(summary: summary, sampled: @report[:sampled].map(&:to_h), scanned: @report[:scanned].map(&:to_h))

      def summary
        sampled = @report[:sampled]
        scanned = @report[:scanned]
        {sampled_findings: sampled.size, sampled_occurrences: sampled.sum(&:count), sampled_resources: sampled.map(&:resource).uniq.size,
         scanned_untranslated: scanned.size, scanned_files: scanned.map(&:file).uniq.size}
      end

      def to_markdown
        s = summary
        lines = ["# Styles report", "",
          "Classes and inline styles with no typed layout, from `rake reactiveadmin:styles`. Values are CSS, not data.", "",
          "**#{s[:sampled_findings]}** distinct findings (#{s[:sampled_occurrences]} occurrences) in #{s[:sampled_resources]} sampled resources; " \
          "**#{s[:scanned_untranslated]}** untranslatable strings in #{s[:scanned_files]} source files.", "",
          "## Sampled: what the API degrades on", ""]
        lines.concat(@report[:sampled].empty? ? ["None."] : sampled_lines)
        lines.concat(["", "## Source scan: every untranslatable string in `app/admin` and `app/views/admin`", ""])
        lines.concat(@report[:scanned].empty? ? ["None."] : scanned_lines)
        lines.join("\n") + "\n"
      end

      private

      def sampled_lines
        @report[:sampled].group_by(&:resource).flat_map do |resource, findings|
          ["### #{resource}", "", "| Kind | Value | Untranslated | Count | Source | Instead |", "| --- | --- | --- | ---: | --- | --- |",
            *findings.map { "| #{it.kind} | #{cell(it.value)} | #{cell(it.untranslated)} | #{it.count} | #{cell(it.sources.first(3).join(", "))} | #{cell(it.advice)} |" }, ""]
        end
      end

      def scanned_lines
        @report[:scanned].group_by(&:file).flat_map do |file, items|
          ["### #{file}", "", "| Line | Kind | Value | Untranslated | Instead |", "| ---: | --- | --- | --- | --- |",
            *items.map { "| #{it.line} | #{it.kind} | #{cell(it.value)} | #{cell(it.untranslated)} | #{cell(it.advice)} |" }, ""]
        end
      end

      def cell(text) = text.to_s.empty? ? "" : "`#{text.to_s.tr("|`", "/'")}`"
    end

    module CLI
      module_function

      def run(env = ENV, out: $stdout)
        report = StyleReport.run(sample: env["SAMPLE"] != "0")
        renderer = Renderer.new(report)
        text = (env["FORMAT"] == "json") ? renderer.to_json : renderer.to_markdown
        return out.puts(text) unless env["OUT"].present?

        File.write(env["OUT"], text)
        out.puts("styles report written to #{env["OUT"]}: #{renderer.summary}")
      end
    end
  end
end
