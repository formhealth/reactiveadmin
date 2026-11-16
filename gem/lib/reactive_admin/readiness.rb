require "json"

module ReactiveAdmin
  # Behind `rake reactiveadmin:readiness`: per resource and page, how it renders in the new admin (the doctor's
  # view of it) and a checklist of signals for leaving classic. It knows what the doctor can measure and what
  # the host records through `config.event_counts`; who still uses classic, and whether anyone is satisfied, it
  # can't see, so a check with no data reads `unknown` rather than passing.
  module Readiness
    SECTIONS = Doctor::SECTIONS
    FALLBACK_MODES = %w[frame iframe].freeze
    EVENTS = {degraded: Degradation::EVENT, client_errors: ClientError::EVENT}.freeze

    module_function

    # `report` is a Doctor report. Rows are resources, then pages.
    def build(report, counts: ReactiveAdmin.config.event_counts)
      rows = [*report[:resources].map { resource_row(it, counts, report[:sampled]) }, *report[:pages].map { page_row(it, counts, report[:sampled]) }]
      {sampled: report[:sampled], counted: !counts.nil?, summary: summary(rows), rows:}
    end

    def resource_row(row, counts, sampled)
      failures = [*row[:failures], *("form is not submittable" if row.dig(:form, :submittable) == false), *render_errors(row)]
      fallbacks = [*row[:actions].select { FALLBACK_MODES.include?(it[:mode]) }.map { it[:name] }, *framed(row)]
      html = SECTIONS.filter_map { |section| "#{section} #{row.dig(section, :html)}" if row.dig(section, :html).to_i.positive? }
      mode = mode_of(fallback: failures.any? || fallbacks.any?, degraded: html.any? || row[:filters][:skipped].any?)
      unsampled = SECTIONS.reject { inspected?(it, row[it]) }
      rendered = unsampled.size < SECTIONS.size
      checks = [
        check("typed views", fallbacks.empty?, "#{fallbacks.join(", ")} through frame or iframe"),
        sample_check(sampled, rendered || failures.any?, failures, unsampled),
        html_check(sampled, rendered, html, unsampled),
        check("all filters built", row[:filters][:skipped].empty?, "skipped #{row[:filters][:skipped].join(", ")}"),
        *event_checks(counts, row[:key], Registry.find(row[:key]))
      ]
      {key: row[:key], kind: "resource", mode:, checks:, ready: ready?(checks)}
    end

    def page_row(row, counts, sampled)
      html = row.dig(:nodes, :html).to_i
      views = [("page through #{row[:mode]}" if FALLBACK_MODES.include?(row[:mode])),
        *row[:actions].to_a.select { FALLBACK_MODES.include?(it[:mode]) }.map { "#{it[:name]} through #{it[:mode]}" },
        *framed(nodes: row[:nodes]).map { "#{it} through frame or iframe" }].compact
      failures = [row[:failure], *render_errors(nodes: row[:nodes])].compact
      mode = mode_of(fallback: failures.any? || views.any?, degraded: html.positive?)
      rendered = inspected?(:page, row[:nodes])
      checks = [
        check("typed views", views.empty?, views.join(", ")),
        sample_check(sampled, rendered || failures.any?, failures),
        html_check(sampled, rendered, ["html nodes #{html}"].reject { html.zero? }),
        *event_checks(counts, row[:key], Registry.pages.find { it.underscored_resource_name == row[:key] })
      ]
      {key: row[:key], kind: "page", mode:, checks:, ready: ready?(checks)}
    end

    # An empty tally (an index with no rows, a layout with no nodes) rendered, but showed nothing to judge.
    def inspected?(section, tally)
      return false unless tally.is_a?(Hash) && !tally.key?(:skipped)

      (tally[:typed].to_i + tally[:html].to_i + tally[:errors].to_i + tally[:frames].to_i).positive? || (section == :index && tally[:rows].to_i.positive?)
    end

    # Sections whose sample embedded a classic page (content that runs its own JavaScript).
    def framed(row)
      row.filter_map { |section, tally| section.to_s if tally.is_a?(Hash) && tally[:frames].to_i.positive? }
    end

    # Values that failed inside a sample that answered 200, so no request failure names them.
    def render_errors(row)
      row.filter_map { |section, tally| "#{section} #{tally[:errors]} failed to render" if tally.is_a?(Hash) && tally[:errors].to_i.positive? }
    end

    def mode_of(fallback:, degraded:)
      return "fallback" if fallback

      degraded ? "degraded" : "native"
    end

    def summary(rows)
      modes = rows.map { it[:mode] }.tally
      {total: rows.size, native: modes.fetch("native", 0), degraded: modes.fetch("degraded", 0), fallback: modes.fetch("fallback", 0), ready: rows.count { it[:ready] }}
    end

    def ready?(checks) = checks.none? { it[:status] == :fail }

    def check(name, ok, detail) = {name:, status: ok ? :pass : :fail, detail: ok ? nil : detail}

    # The doctor samples a screen only with a sample user, and skips nested resources, guarded sections and
    # pages that need a record; without a sample there is nothing to read.
    def sample_check(sampled, evidence, failures, unsampled = [])
      return unmeasured("samples render", sampled, unsampled) unless evidence

      partial(check("samples render", failures.empty?, failures.join("; ")), unsampled)
    end

    def html_check(sampled, evidence, html, unsampled = [])
      return unmeasured("no html leaves", sampled, unsampled) unless evidence

      partial(check("no html leaves", html.empty?, html.join(", ")), unsampled)
    end

    def unmeasured(name, sampled, unsampled = [])
      detail = sampled ? "not sampled for this screen" : "not sampled; set config.doctor_user"
      {name:, status: :unknown, detail: [detail, *(unsampled_detail(unsampled) if sampled)].join("; ")}
    end

    def partial(check, unsampled) = (check[:status] == :pass && unsampled.any?) ? check.merge(detail: unsampled_detail(unsampled)) : check

    def unsampled_detail(unsampled) = ("nothing to inspect in #{unsampled.join(", ")}" if unsampled.any?)

    def event_checks(counts, key, config)
      EVENTS.map do |name, event|
        count = recent(counts, event, event_resource(event, key, config))
        label = "no #{name.to_s.tr("_", " ")}"
        next {name: label, status: :unknown, detail: "not recorded; set config.event_counts"} unless count

        check(label, count.zero?, "#{count} recent")
      end
    end

    # Each event publishes `resource` its own way: `degraded` as the model's name, the rest as the route key.
    def event_resource(event, key, config) = (event == Degradation::EVENT) ? (config&.resource_name&.to_s || key) : key

    def recent(counts, event, resource)
      Integer(counts&.call(event, resource), exception: false)
    rescue => e
      Rails.logger.warn("[reactiveadmin] event_counts raised #{e.class}; counts left unknown")
      nil
    end

    # Text rendering of a build.
    class Table
      CANT_SEE = [
        "who still uses classic (log the `reactiveadmin_ui` cookie, or `ui.default` changes)",
        "whether operators can do their work in the new admin: ask them",
        "screens the doctor did not sample: nested resources and actions that need a record"
      ].freeze

      def initialize(result)
        @result = result
      end

      def to_s
        [header, rows, blockers, "Not visible to the gem\n#{CANT_SEE.map { "  - #{it}" }.join("\n")}"].compact.join("\n\n")
      end

      private

      attr_reader :result

      def header
        s = result[:summary]
        lines = ["reactiveadmin readiness#{" (static: no sample user)" unless result[:sampled]}",
          "  #{s[:total]} resources and pages: native #{s[:native]}, degraded #{s[:degraded]}, fallback #{s[:fallback]}; ready to leave classic #{s[:ready]}",
          ("  event counts are not recorded; see `config.event_counts`" unless result[:counted])]
        lines.compact.join("\n")
      end

      def rows
        width = result[:rows].map { label(it).size }.max || 0
        lines = result[:rows].map do |row|
          name = label(row)
          unknown = row[:checks].count { it[:status] == :unknown }
          "  #{name.ljust(width)}  #{row[:mode].ljust(8)}  #{row[:ready] ? "ready" : "not ready"}#{" (#{unknown} unknown)" if unknown.positive?}"
        end
        "Resources and pages\n#{lines.join("\n")}"
      end

      def label(row) = (row[:kind] == "page") ? "page #{row[:key]}" : row[:key]

      def blockers
        lines = result[:rows].flat_map do |row|
          row[:checks].select { it[:status] == :fail }.map { "  #{label(row)}: #{it[:name]} (#{it[:detail]})" }
        end
        ("Blocking\n#{lines.join("\n")}" if lines.any?)
      end
    end

    # The rake task's driver; options come from the environment so they pass through `rake`.
    module CLI
      module_function

      def run(env = ENV, out: $stdout)
        result = Readiness.build(Doctor.run(sample: env["SAMPLE"] != "0"))
        out.puts((env["FORMAT"] == "json") ? JSON.pretty_generate(result) : Table.new(result))
        result
      end
    end
  end
end
