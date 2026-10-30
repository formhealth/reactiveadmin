module ReactiveAdmin
  # Finds the host source lines behind a class or inline style, for `doctor`. While tracing, Arbre
  # tags note the DSL line that built them; markup from ERB and helpers is found by scanning the
  # app's templates. Only runs under doctor, so requests never pay for it.
  module StyleSources
    KEY = :reactiveadmin_style_sources
    STATE = ActiveSupport::IsolatedExecutionState
    SCAN = "app/**/*.{rb,erb,arb,haml,slim}".freeze
    LIMIT = 3
    OWN = File.expand_path("..", __dir__)

    # Arbre calls `build` for every tag, with the attributes the DSL line passed.
    module Tracer
      def build(*args, &block)
        super.tap { StyleSources.note(self) if StyleSources.tracing? }
      end
      ruby2_keywords :build
    end

    Line = Data.define(:file, :number, :text)

    module_function

    def tracing? = !STATE[KEY].nil?

    def trace
      return yield if tracing?

      install
      STATE[KEY] = {}
      begin
        yield
      ensure
        STATE[KEY] = nil
        @lines = nil
      end
    end

    # "app/admin/x.rb:12, app/views/admin/y.erb:3" for a class token or a whole style attribute of
    # a resource's page (by `resource_name`, as the walker labels it).
    def locate(string, resource: nil)
      string = string.to_s.squish
      return if string.empty? || !tracing?

      (STATE[KEY][[resource.to_s, string]]&.to_a.presence || scan(string)).first(LIMIT).join(", ").presence
    end

    def note(tag)
      style = tag.get_attribute(:style).to_s.squish
      strings = [style, *tag.class_names.split].reject(&:empty?)
      where = origin if strings.any?
      return unless where

      resource = tag.arbre_context.helpers.try(:active_admin_config)&.resource_name.to_s
      strings.each { (STATE[KEY][[resource, it]] ||= Set.new) << where }
    end

    def origin
      root = "#{Rails.root}/"
      frame = caller_locations.find do |location|
        path = location.absolute_path.to_s
        path.start_with?(root) && !path.start_with?(OWN) && %w[/gems/ /vendor/].none? { |part| path.include?(part) }
      end
      "#{frame.absolute_path.delete_prefix(root)}:#{frame.lineno}" if frame
    end

    def install
      AA.trace_arbre_tags(Tracer)
    end

    def scan(string)
      pattern = /(?<![\w:\/\[-])#{Regexp.escape(string)}(?![\w-])/
      lines.select { it.text.match?(pattern) }.map { "#{it.file}:#{it.number}" }
    end

    def lines
      @lines ||= Rails.root.glob(SCAN).sort.flat_map do |path|
        file = path.relative_path_from(Rails.root).to_s
        path.each_line.with_index(1).map { |text, number| Line.new(file:, number:, text: text.scrub) }
      end
    end
  end
end
