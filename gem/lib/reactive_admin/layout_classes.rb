module ReactiveAdmin
  # Translates a safelisted subset of utility classes, and of inline styles (via InlineStyle, which
  # speaks in the same classes), into hints for the client. Raw classes and styles are never passed
  # through: what has no translation is returned in `unknown` and `unknown_styles` for `doctor`.
  class LayoutClasses
    BREAKPOINTS = %w[sm md lg xl].freeze
    WIDTHS = %w[1/4 1/3 1/2 2/3 3/4 full].freeze
    MAX_WIDTHS = %w[sm md lg xl 2xl].freeze
    ALIGNS = %w[start center end stretch baseline].freeze
    JUSTIFIES = %w[start center end between].freeze
    TEXT_ALIGNS = %w[left center right].freeze
    # Colors say what the text means; the client picks the shade.
    TONES = {"muted" => "muted", "gray" => "muted", "grey" => "muted", "success" => "success", "green" => "success",
             "danger" => "danger", "red" => "danger", "warning" => "warning", "yellow" => "warning", "orange" => "warning",
             "amber" => "warning"}.freeze
    MAX_GAP = 8
    MAX_SPACING = 8
    MAX_COLUMNS = 12
    # Plain-word utilities. Other plain words (button, empty, ...) are AA's own semantic classes.
    UTILITY_WORDS = %w[hidden block inline contents relative absolute fixed sticky truncate underline italic uppercase
      lowercase capitalize grow shrink container].freeze
    # A dashed class is a utility when it starts like one; `button-secondary` or `nav-tabs` is the host's or AA's own.
    UTILITY_FAMILY = /\A-?(?:[mp][trblxy]?|(?:min|max)-[wh]|[wh]|size|gap|space|flex|grid|col|row|basis|order|items|justify|content|self|place|
      text|font|leading|tracking|bg|border|divide|ring|outline|rounded|shadow|opacity|overflow|object|cursor|whitespace|break|z|top|right|bottom|
      left|inset|align|list|decoration|transition|duration|translate|rotate|scale|transform|float|clear|aspect|columns|sr|indent|fill|stroke)-/x
    SIDES = {"t" => %i[top], "r" => %i[right], "b" => %i[bottom], "l" => %i[left], "x" => %i[left right], "y" => %i[top bottom],
             "" => %i[top right bottom left]}.freeze

    Result = Struct.new(:layout, :width, :span, :text_align, :justify, :spacing, :max_width, :grow, :marks, :tone, :nowrap, :unknown, :unknown_styles) do
      # Contract fields for a box; empty when the classes say nothing about layout.
      def hints = {layout:, width:, span:, text_align:, spacing:, max_width:, grow:}.compact

      # Contract fields for text, or for a box whose content they apply to.
      def text_style = {marks:, tone:, nowrap:}.compact

      # Where a toolbar's content sits, from `text-right` or `justify-end`.
      def toolbar_align = {"right" => "end", "center" => "center", "end" => "end"}[text_align || justify]
    end

    def self.parse(classes, style: nil) = new(classes, style:).parse

    # What to use instead of an untranslatable class, for the styles report.
    ADVICE = {
      /\A(?:[a-z]+:)?-?[mp][trblxy]?-\d+\z/ => "margins go up to 8 (2rem), unprefixed and positive; padding has no typed equivalent (wrap in a panel)",
      /\A(?:[a-z]+:)?(?:bg|border|rounded|shadow|ring)(?:-|\z)/ => "no typed fill or border; use a panel or a `flash`",
      /\A(?:[a-z]+:)?text-(?:xs|sm|base|lg|xl|\dxl)\z/ => "no typed text size; drop it",
      /\A(?:[a-z]+:)?max-w-/ => "use `max-w-sm|md|lg|xl|2xl`",
      /\A(?:[a-z]+:)?(?:w|basis)-/ => "use `w-1/4|1/3|1/2|2/3|3/4|full`",
      /\A[a-z]+:/ => "responsive variants only read for flex-row, grid-cols, w and col-span"
    }.freeze

    def self.advice(token) = ADVICE.find { |pattern, _| token.match?(pattern) }&.last || "no typed equivalent"

    def initialize(classes, style: nil)
      translated = InlineStyle.parse(style)
      @tokens = [*classes.to_s.split, *translated.tokens]
      @unknown_styles = translated.unknown
      @responsive_rows = []
      @responsive_columns = []
      @responsive_widths = {}
      @responsive_spans = {}
      @gap = 0
      @wrap = false
      @spacing = {}
      @marks = []
    end

    def parse
      unknown = @tokens.select { !handled?(*split(it)) && utility?(it) }
      Result.new(layout:, width: @responsive_widths.values.first || @width, span: @responsive_spans.values.first || @span,
        text_align: @text_align, justify: @justify, spacing: @spacing.presence, max_width: @max_width, grow: (true if @grow),
        marks: @marks.presence, tone: @tone, nowrap: (true if @nowrap), unknown:, unknown_styles: @unknown_styles)
    end

    private

    def split(token)
      prefix, _, base = token.rpartition(":")
      [prefix.presence, base]
    end

    def utility?(token) = token.match?(/[:\/\[]/) || token.match?(UTILITY_FAMILY) || UTILITY_WORDS.include?(token)

    def handled?(prefix, base)
      return false if prefix && BREAKPOINTS.exclude?(prefix)

      case base
      when "flex", "inline-flex" then !prefix && (@display ||= "flex")
      when "grid" then !prefix && (@display = "grid")
      when "flex-row" then prefix ? @responsive_rows << prefix : (@direction = "row")
      when "flex-col" then !prefix && (@direction = "column")
      when "flex-wrap" then !prefix && (@wrap = true)
      when "flex-nowrap" then !prefix
      when /\Agap-(\d+)\z/ then !prefix && (@gap = [$1.to_i, MAX_GAP].min)
      when /\Aitems-(\w+)\z/ then !prefix && ALIGNS.include?($1) && (@align = $1)
      when /\Ajustify-(\w+)\z/ then !prefix && JUSTIFIES.include?($1) && (@justify = $1)
      when "w-auto" then !prefix
      when /\A(?:w|basis)-(.+)\z/ then width($1, prefix)
      when /\Amax-w-(\w+)\z/ then !prefix && MAX_WIDTHS.include?($1) && (@max_width = $1)
      when "grow", "flex-grow", "flex-1" then !prefix && (@grow = true)
      when /\Am([trblxy]?)-(\d+)\z/ then !prefix && spacing($1, $2.to_i)
      when "font-bold", "font-semibold" then !prefix && mark("strong")
      when "italic" then !prefix && mark("em")
      when "whitespace-nowrap", "text-nowrap" then !prefix && (@nowrap = true)
      when /\Atext-(\w+)\z/ then !prefix && (TEXT_ALIGNS.include?($1) ? (@text_align = $1) : tone($1))
      when /\Atext-(\w+)-\d+\z/ then !prefix && tone($1)
      when /\Agrid-cols-(\d+)\z/ then columns($1.to_i, prefix)
      when /\Acol-span-(\d+)\z/ then span($1.to_i, prefix)
      else false
      end
    end

    def width(value, prefix)
      return false unless WIDTHS.include?(value)

      prefix ? @responsive_widths[prefix] = value : @width = value
    end

    # A zero margin only resets classic's defaults, which the client doesn't have.
    def spacing(side, steps)
      return false if steps > MAX_SPACING

      SIDES.fetch(side).each { @spacing[it] = steps } if steps.positive?
      true
    end

    def mark(name)
      @marks << name unless @marks.include?(name)
      true
    end

    def tone(name) = TONES.key?(name) && (@tone = TONES[name])

    def columns(count, prefix)
      return false unless (1..MAX_COLUMNS).cover?(count)

      prefix ? @responsive_columns << [prefix, count] : @columns = count
    end

    def span(count, prefix)
      return false unless (1..MAX_COLUMNS).cover?(count)

      prefix ? @responsive_spans[prefix] = count : @span = count
    end

    def layout
      case @display
      when "flex" then flex
      when "grid" then grid
      end
    end

    # `flex lg:flex-row` means stacked below lg, even though plain `flex` is a row at every width.
    def flex
      breakpoint = @responsive_rows.min_by { BREAKPOINTS.index(it) } unless @direction == "row"
      {display: "flex", direction: breakpoint ? "row" : (@direction || "row"), breakpoint:, gap: @gap, wrap: @wrap}
        .merge({align: @align, justify: @justify}.compact)
    end

    def grid
      breakpoint, count = @responsive_columns.min_by { BREAKPOINTS.index(it.first) }
      layout = {display: "grid", columns: count || @columns || 1, breakpoint:, gap: @gap}
      layout[:base_columns] = @columns if breakpoint && @columns && @columns != 1
      layout
    end
  end
end
