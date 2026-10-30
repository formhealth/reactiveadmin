module ReactiveAdmin
  # Reads an inline style as the utility classes LayoutClasses understands, one declaration at a
  # time. Only values that land exactly on the vocabulary translate; anything else is returned in
  # `unknown` and never reaches a typed node.
  class InlineStyle
    PX_PER_STEP = 4
    MAX_REPORTED = 200
    SIDES = {"top" => "t", "right" => "r", "bottom" => "b", "left" => "l"}.freeze
    SHARES = {25.0 => "1/4", 33.333 => "1/3", 50.0 => "1/2", 66.667 => "2/3", 75.0 => "3/4", 100.0 => "full"}.freeze
    ALIGN_ITEMS = {"flex-start" => "start", "start" => "start", "center" => "center", "flex-end" => "end", "end" => "end",
                   "stretch" => "stretch", "baseline" => "baseline"}.freeze
    JUSTIFY = {"flex-start" => "start", "start" => "start", "center" => "center", "flex-end" => "end", "end" => "end",
               "space-between" => "between"}.freeze
    BOLD = %w[bold bolder 600 700 800 900].freeze
    COLORS = {"#999" => "muted", "#999999" => "muted", "gray" => "muted", "grey" => "muted", "red" => "danger", "green" => "success"}.freeze

    # What to do with a declaration that has no translation, for the styles report.
    ADVICE = {
      "padding" => "no typed equivalent; wrap in a panel, or use margin on the neighbours",
      "position" => "classic-only layout; the client sizes and scrolls its own panes",
      "overflow" => "classic-only; the client scrolls its own panes",
      "max-height" => "classic-only; drop it",
      "max-width" => "use `max-w-sm|md|lg|xl|2xl`",
      "width" => "use `w-1/4|1/3|1/2|2/3|3/4|full`, or `max-w-*`",
      "color" => "use `text-muted|success|danger|warning`",
      "background" => "use a `flash` or a status_tag for a callout; there is no typed fill",
      "border" => "use a panel or a `flash`; there is no typed border",
      "cursor" => "drop it; the client styles its own controls",
      "font-family" => "drop it, or show the text as a `code` node",
      "font-size" => "drop it; there is no typed text size",
      "display" => "drop it; boxes are blocks (use `flex` for rows)",
      "white-space" => "only `nowrap` has a typed form (`whitespace-nowrap`); show preformatted text as a `code` node",
      "flex-shrink" => "drop it; the client handles shrink",
      "top" => "classic-only layout",
      "bottom" => "classic-only layout",
      "margin" => "use margins on the 4px scale (`mt-2`), no negatives or auto",
      "margin-top" => "use margins on the 4px scale (`mt-2`), no negatives or auto",
      "margin-bottom" => "use margins on the 4px scale (`mb-2`), no negatives or auto",
      "margin-left" => "use margins on the 4px scale (`ml-2`), no negatives or auto",
      "margin-right" => "use margins on the 4px scale (`mr-2`), no negatives or auto"
    }.freeze

    Result = Struct.new(:tokens, :unknown)

    def self.parse(style) = new(style).parse

    # A style a host builds from data can carry some (a url, a width), so reports keep it short and drop urls.
    def self.redact(style) = style.to_s.squish.gsub(/url\([^)]*\)/i, "url(…)").truncate(MAX_REPORTED)

    def self.advice(declaration) = ADVICE.fetch(declaration.to_s.split(":").first.to_s.strip.downcase, "no typed equivalent")

    def initialize(style)
      @declarations = style.to_s.split(";").filter_map do |declaration|
        property, _, value = declaration.partition(":")
        [property.strip.downcase, value.sub(/!important\z/i, "").strip.downcase] if property.strip.present? && value.present?
      end
    end

    def parse
      tokens = []
      unknown = []
      @declarations.each do |property, value|
        translated = translate(property, value)
        translated ? tokens.concat(translated) : unknown << "#{property}: #{value}"
      end
      Result.new(tokens, unknown)
    end

    private

    # nil means no translation; an empty list means the declaration says nothing the client needs.
    def translate(property, value)
      case property
      when /\Amargin-(top|right|bottom|left)\z/ then spacing("m#{SIDES[$1]}", value)
      when "margin" then margin(value)
      when "text-align" then %W[text-#{value}] if LayoutClasses::TEXT_ALIGNS.include?(value)
      when "display" then {"flex" => %w[flex], "inline-flex" => %w[inline-flex], "grid" => %w[grid]}[value]
      when "flex-direction" then {"row" => %w[flex-row], "column" => %w[flex-col]}[value]
      when "flex-wrap" then {"wrap" => %w[flex-wrap], "nowrap" => []}[value]
      when "white-space" then {"nowrap" => %w[whitespace-nowrap], "normal" => []}[value]
      when "gap" then steps(value)&.then { ["gap-#{it}"] }
      when "align-items" then ALIGN_ITEMS[value]&.then { ["items-#{it}"] }
      when "justify-content" then JUSTIFY[value]&.then { ["justify-#{it}"] }
      when "width" then width(value)
      when "font-weight" then BOLD.include?(value) ? %w[font-bold] : ([] if %w[normal 400].include?(value))
      when "font-style" then {"italic" => %w[italic], "normal" => []}[value]
      when "color" then COLORS[value]&.then { ["text-#{it}"] }
      when "flex" then ["grow"] if ["1", "1 1 0", "1 1 0%", "1 1 0px"].include?(value)
      when "flex-grow" then %w[grow] if value == "1"
      end
    end

    # Whole steps of the 4px scale, from px or rem; 0 is a valid step.
    def steps(value)
      amount, unit = value.match(/\A(\d+(?:\.\d+)?)(px|rem)?\z/)&.captures
      return unless amount

      pixels = (unit == "rem") ? amount.to_f * 16 : amount.to_f
      return 0 if pixels.zero?
      return unless unit && pixels % PX_PER_STEP == 0

      (pixels / PX_PER_STEP).to_i.then { it if it <= LayoutClasses::MAX_SPACING }
    end

    def spacing(prefix, value) = steps(value)&.then { ["#{prefix}-#{it}"] }

    # CSS order: top, right, bottom, left, each repeating from the opposite side when omitted.
    def margin(value)
      parts = value.split
      return unless (1..4).cover?(parts.size)

      top, right, bottom, left = parts.values_at(0, 1, 2, 3)
      sides = {"t" => top, "r" => right || top, "b" => bottom || top, "l" => left || right || top}
      tokens = sides.map { |side, part| spacing("m#{side}", part) }
      tokens.flatten if tokens.none?(&:nil?)
    end

    def width(value)
      return unless value.end_with?("%")

      percent = value.to_f
      SHARES.find { |amount, _| (amount - percent).abs < 0.1 }&.last&.then { ["w-#{it}"] }
    end
  end
end
