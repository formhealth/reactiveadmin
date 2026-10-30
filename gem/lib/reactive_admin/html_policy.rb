module ReactiveAdmin
  # The one sanitizer policy for server-rendered HTML. `display` is for html nodes inside content;
  # `interactive` is for frame nodes (forms allowed); `neutralize_frame` hardens the body of a frame
  # response. `rake reactiveadmin:html_policy` prints `export` so the client configures DOMPurify
  # from the same lists instead of keeping its own.
  module HtmlPolicy
    VERSION = 6
    # Nokogiri raises past its tree depth, and stored markup can be arbitrarily large: parse under caps and
    # degrade instead of failing the whole response.
    MAX_TREE_DEPTH = 256
    MAX_NODES = 2_000
    MAX_BYTES = 100.kilobytes
    TOO_COMPLEX = "This content is too complex to display".freeze
    URI_SCHEMES = %w[http https mailto tel].freeze
    DISPLAY_TAGS = %w[a abbr acronym address b big blockquote br caption cite code dd del details dfn div dl dt em embed
      h1 h2 h3 h4 h5 h6 hr i img ins kbd li mark object ol p pre samp small span strong sub summary sup table tbody td tfoot
      th thead time tr tt ul var].freeze
    # No class: stored markup must not borrow the host's Tailwind classes to overlay the app.
    DISPLAY_ATTRIBUTES = %w[abbr alt cite data datetime height href lang loading referrerpolicy rel src style
      target title type width xml:lang].freeze
    FORM_TAGS = %w[button datalist fieldset form input label legend optgroup option select textarea].freeze
    FORM_ATTRIBUTES = %w[action autocomplete checked cols data-confirm data-disable-with data-method data-remote disabled
      enctype for id list max maxlength method min minlength multiple novalidate pattern placeholder readonly required rows
      selected step value].freeze
    FRAME_TAGS = (DISPLAY_TAGS + FORM_TAGS).freeze
    # `class` is stripped from frames, so the classic widgets the client replaces are marked with this
    # attribute (value => selector, matched before the strip) instead of being found by class.
    WIDGET_ATTRIBUTE = "data-reactiveadmin-widget".freeze
    WIDGETS = {"date" => "input.datepicker"}.freeze
    FRAME_ATTRIBUTES = (DISPLAY_ATTRIBUTES + FORM_ATTRIBUTES + %w[name] + [WIDGET_ATTRIBUTE]).freeze
    # `name` submits a value only from a form control; anywhere else it is a DOM clobbering hook.
    NAMED_TAGS = %w[button input select textarea].freeze
    # Named access on document and form elements shadows their own properties, so these names are unusable.
    CLOBBERED_NAMES = %w[action body cookie defaultView document domain elements forms head location reset submit URL window].freeze

    # Tag => the attribute holding its URL. Only the same site (or a configured trusted host) may load them.
    MEDIA = {"img" => "src", "embed" => "src", "object" => "data", "iframe" => "src"}.freeze
    MEDIA_LABELS = {"img" => "External image", "embed" => "External document", "object" => "External document", "iframe" => "External page"}.freeze
    # A same-site embed must declare a safe type and have a matching path; otherwise a same-site HTML page
    # (an admin screen, say) would render inside the frame.
    EMBED_TYPES = %w[application/pdf].freeze
    EMBED_EXTENSIONS = %w[.pdf].freeze
    FORCED_ATTRIBUTES = {"img" => {"referrerpolicy" => "no-referrer", "loading" => "lazy"}}.freeze
    DATA_IMAGE = %r{\Adata:image/(?:png|jpe?g|gif|webp|bmp);base64,[A-Za-z0-9+/=\s]+\z}i
    FRAME_REMOVED_TAGS = %w[script base].freeze
    FRAME_TARGET_ATTRIBUTES = %w[action formaction].freeze
    UNSAFE_URL = /\A(?:javascript|vbscript):/i
    UNSAFE_NAVIGATION_URL = /\A(?:javascript|vbscript|data):/i

    # Inline styles are held to layout properties with a closed value grammar; each pattern must match the whole
    # value, which is lowercased with whitespace collapsed first. No colors, positioning, stacking, images or url():
    # those turn style into UI redressing or a request channel. The client applies the same table from `export`.
    # No negative lengths (a negative margin pulls content over its neighbours) and no viewport units (vw/vh
    # overlay the page). The digit cap keeps a value from sizing a block past any screen.
    NUMBER = '(?:\d{1,4}(?:\.\d*)?|\.\d+)'
    LENGTH = "(?:0|#{NUMBER}(?:px|em|rem|ch|%))"
    SPACING = "(?:#{LENGTH}|auto)(?: (?:#{LENGTH}|auto)){0,3}"
    PADDING = "#{LENGTH}(?: #{LENGTH}){0,3}"
    GAP = "(?:#{LENGTH}|normal)(?: (?:#{LENGTH}|normal))?"
    ALIGNMENT = "(?:stretch|center|flex-start|flex-end|start|end|baseline|normal)"
    DECORATION = "(?:underline|overline|line-through)"
    STYLE_PROPERTIES = {
      "display" => "(?:block|inline|inline-block|flex|inline-flex|grid|none)",
      "text-align" => "(?:left|right|center|justify|start|end)",
      "vertical-align" => "(?:baseline|top|middle|bottom|text-top|text-bottom|sub|super)",
      "white-space" => "(?:normal|nowrap|pre|pre-wrap|pre-line|break-spaces)",
      "font-weight" => "(?:normal|bold|bolder|lighter|[1-9]00)",
      "font-style" => "(?:normal|italic|oblique)",
      "text-decoration" => "(?:none|#{DECORATION}(?: #{DECORATION}){0,2})",
      "gap" => GAP, "row-gap" => GAP, "column-gap" => GAP,
      "flex" => "(?:none|auto|initial|#{NUMBER}(?: #{NUMBER})?(?: (?:#{LENGTH}|auto|content))?)",
      "flex-direction" => "(?:row|row-reverse|column|column-reverse)",
      "flex-wrap" => "(?:nowrap|wrap|wrap-reverse)",
      "flex-grow" => NUMBER, "flex-shrink" => NUMBER,
      "flex-basis" => "(?:#{LENGTH}|auto|content)",
      "align-items" => ALIGNMENT,
      "align-self" => "(?:auto|#{ALIGNMENT})",
      "justify-content" => "(?:flex-start|flex-end|start|end|center|space-between|space-around|space-evenly|normal)",
      "list-style-type" => "(?:none|disc|circle|square|decimal|lower-alpha|upper-alpha|lower-roman|upper-roman|lower-latin|upper-latin)",
      "border-collapse" => "(?:collapse|separate)",
      "float" => "(?:left|right|none)",
      "clear" => "(?:none|left|right|both)"
    }.merge(
      %w[margin margin-top margin-right margin-bottom margin-left].to_h { [it, SPACING] },
      %w[padding padding-top padding-right padding-bottom padding-left].to_h { [it, PADDING] },
      %w[width min-width max-width height min-height max-height].to_h { [it, "(?:#{LENGTH}|auto|none)"] }
    ).freeze
    STYLE_FORBIDDEN_VALUES = ["url(", "expression", "@import", "\\", "javascript:", "behavior", "-moz-binding", "/*"].freeze
    STYLE_PATTERNS = STYLE_PROPERTIES.transform_values { Regexp.new("\\A(?:#{it})\\z") }.freeze

    # Scrubs style with the table above instead of Loofah's CSS cleaner, which would let color through and drop gap.
    class StyleScrubber < Rails::HTML::PermitScrubber
      def scrub_css_attribute(node)
        return unless (attribute = node.attribute_nodes.find { it.name == "style" })

        style = HtmlPolicy.style(attribute.value)
        style.empty? ? attribute.remove : attribute.value = style
      end
    end

    module_function

    # Keeps only the allowlisted declarations, normalized to "prop: value; prop: value".
    def style(css)
      css.to_s.split(";").filter_map { style_declaration(it) }.join("; ")
    end

    def style_declaration(declaration)
      property, value = declaration.split(":", 2)
      return unless value

      property = tidy(property)
      value = tidy(value)
      return unless STYLE_PATTERNS[property]&.match?(value) && STYLE_FORBIDDEN_VALUES.none? { value.include?(it) }

      "#{property}: #{value}"
    end

    # ASCII-only whitespace on purpose: the client must trim exactly the same characters.
    def tidy(text) = text.downcase.gsub(/[ \t\r\n\f]+/, " ").delete_prefix(" ").delete_suffix(" ")

    def display(html, host: nil, where: nil)
      fragment = parse(html, where:) or return TOO_COMPLEX
      fragment.css("script, style").remove
      restrict_media(fragment, host:, where:)
      allow(fragment.to_html, DISPLAY_TAGS, DISPLAY_ATTRIBUTES)
    end

    def interactive(html, host: nil, where: nil)
      fragment = parse(html, where:) or return TOO_COMPLEX
      neutralize_frame(fragment, host:, where:)
      allow(fragment.to_html, FRAME_TAGS, FRAME_ATTRIBUTES)
    end

    # For a whole classic response, which is not cut down to an allowlist: the client sanitizes it again.
    def frame_body(html, host: nil, where: nil)
      fragment = parse(html, where:) or return TOO_COMPLEX
      neutralize_frame(fragment, host:, where:)
      fragment.css("[style]").each { restyle(it) }
      fragment.to_html
    end

    # nil when the markup is too deep to parse; callers show TOO_COMPLEX instead.
    def parse(html, where: nil)
      truncate_nodes(Nokogiri::HTML5.fragment(truncate_bytes(html.to_s, where:), max_tree_depth: MAX_TREE_DEPTH), where:)
    rescue ArgumentError
      degrade(:html_too_deep, "Markup nests deeper than #{MAX_TREE_DEPTH} elements; not shown", where:)
      nil
    end

    def truncate_bytes(html, where:)
      return html if html.bytesize <= MAX_BYTES

      degrade(:html_truncated, "Truncated html beyond #{MAX_BYTES} bytes", where:)
      html.byteslice(0, MAX_BYTES).scrub("")
    end

    def truncate_nodes(fragment, where:)
      extra = fragment.xpath(".//*").drop(MAX_NODES)
      return fragment if extra.empty?

      extra.each(&:remove)
      degrade(:html_truncated, "Kept the first #{MAX_NODES} elements of html", where:)
      fragment
    end

    # What the client needs to build the same DOMPurify configuration; see the rake task.
    def export
      {
        version: VERSION,
        style: {properties: STYLE_PROPERTIES, forbidden_values: STYLE_FORBIDDEN_VALUES},
        display: {
          tags: DISPLAY_TAGS, attributes: DISPLAY_ATTRIBUTES, uri_schemes: URI_SCHEMES, trusted_hosts: trusted_hosts,
          embed: {types: EMBED_TYPES, extensions: EMBED_EXTENSIONS},
          media: MEDIA.to_h { |tag, attribute| [tag, {attribute:, same_origin: true, data_image: tag == "img", forced_attributes: FORCED_ATTRIBUTES[tag]}.compact] }
        },
        frame: {
          tags: FRAME_TAGS, attributes: FRAME_ATTRIBUTES, uri_schemes: URI_SCHEMES, trusted_hosts: trusted_hosts,
          removed_tags: FRAME_REMOVED_TAGS, same_origin_attributes: FRAME_TARGET_ATTRIBUTES,
          named_tags: NAMED_TAGS, clobbered_names: CLOBBERED_NAMES,
          widget_attribute: WIDGET_ATTRIBUTE, widgets: WIDGETS,
          media_tags: MEDIA.keys, forced_attributes: FORCED_ATTRIBUTES
        }
      }
    end

    # Relative URLs and the request's own host (and configured trusted hosts) count as the same site. A scheme
    # must be followed by a host (`https:evil.test` and `http:/evil.test` are not relative), and `//` is
    # protocol-relative, so neither can be same-site.
    def same_origin?(url, host)
      url = url.to_s.strip
      return false if url.match?(/[\u0000- \u007f\\]/)

      uri = URI.parse(url)
      if uri.scheme
        %w[http https].include?(uri.scheme.downcase) && uri.host.present? && trusted_host?(uri.host, host)
      else
        !url.start_with?("//")
      end
    rescue URI::InvalidURIError
      false
    end

    def trusted_host?(hostname, host) = [host, *trusted_hosts].compact.any? { hostname.casecmp?(it) }

    def trusted_hosts
      hosts = ReactiveAdmin.config.html_trusted_hosts
      Array(hosts.respond_to?(:call) ? hosts.call : hosts).map(&:to_s)
    end

    # :keep, :drop, or [label, href] for a link that stands in for the element. A same-site
    # iframe is also a link here; HtmlNodes turns one into an iframe node instead.
    def media(el, host:)
      src = source(el)
      return ["Embedded page", src] if el.name == "iframe" && same_origin?(src, host)
      return :keep if loadable?(el, src, host)

      src.match?(%r{\A(?:https?:)?//[^\s]+\z}i) ? [MEDIA_LABELS[el.name], src] : :drop
    end

    def source(el) = el[MEDIA.fetch(el.name)].to_s.strip

    def loadable?(el, src, host)
      case el.name
      when "img" then src.match?(DATA_IMAGE) || same_origin?(src, host)
      when "embed", "object" then same_origin?(src, host) && pdf?(el, src)
      else same_origin?(src, host)
      end
    end

    # A configured trusted host may serve a PDF from an extensionless URL (signed CDN links); same-site paths may not.
    def pdf?(el, src)
      EMBED_TYPES.include?(el["type"].to_s.strip.downcase) && (pdf_path?(src) || trusted_url?(src))
    end

    def pdf_path?(src) = EMBED_EXTENSIONS.any? { src.split(/[?#]/).first.to_s.downcase.end_with?(it) }

    # Absolute http(s) on a configured trusted host, as opposed to this site's own.
    def trusted_url?(url) = url.to_s.strip.match?(%r{\Ahttps?://}i) && same_origin?(url, nil)

    def restrict_media(fragment, host:, where:)
      fragment.xpath("descendant-or-self::*[not(self::img)]/@referrerpolicy | descendant-or-self::*[not(self::img)]/@loading").remove
      fragment.css(MEDIA.keys.join(",")).each do |el|
        case (decision = media(el, host:))
        when :keep then force(el, FORCED_ATTRIBUTES.fetch(el.name, {}))
        when :drop then el.remove
        else
          el.replace(external_link(el.document, *decision))
          degrade(:external_media_blocked, "Replaced an external image or document with a link", where:)
        end
      end
    end

    def force(el, attributes) = attributes.each { |name, value| el[name] = value }

    def external_link(document, label, href)
      Nokogiri::XML::Node.new("a", document).tap do |a|
        a["href"] = href
        a["target"] = "_blank"
        a["rel"] = "noopener noreferrer"
        a.content = label
      end
    end

    def neutralize_frame(fragment, host:, where:)
      fragment.css(FRAME_REMOVED_TAGS.join(",")).remove
      fragment.css("meta[http-equiv]").remove
      fragment.xpath(".//@*[starts-with(local-name(), 'on')] | .//@srcdoc").remove
      fragment.xpath(".//@*").each { it.remove if unsafe_url?(it) }
      clobbering_names(fragment)
      mark_widgets(fragment)
      offsite_targets(fragment, host:, where:)
      fragment.css("img").each { force(it, FORCED_ATTRIBUTES.fetch("img")) }
    end

    # Markup can't claim a widget itself: the attribute is dropped everywhere, then set from the table.
    def mark_widgets(fragment)
      fragment.xpath(".//@#{WIDGET_ATTRIBUTE}").remove
      WIDGETS.each { |widget, selector| fragment.css(selector).each { it[WIDGET_ATTRIBUTE] = widget } }
    end

    def clobbering_names(fragment)
      fragment.css("[name]").each { it.remove_attribute("name") unless NAMED_TAGS.include?(it.name) }
      fragment.css("[name], [id]").each do |el|
        %w[name id].each do |attribute|
          el.remove_attribute(attribute) if CLOBBERED_NAMES.any? { |name| name.casecmp?(el[attribute].to_s) }
        end
      end
    end

    def unsafe_url?(attribute)
      return false unless %w[href src action formaction data poster].include?(attribute.name)

      # Browsers ignore whitespace and control characters inside a scheme.
      value = attribute.value.to_s.gsub(/[\u0000- ]/, "")
      value.match?(%w[href action formaction].include?(attribute.name) ? UNSAFE_NAVIGATION_URL : UNSAFE_URL)
    end

    # Links to other sites stay (a click is the user's choice); what submits or loads is held to this site.
    def offsite_targets(fragment, host:, where:)
      fragment.xpath(".//@action | .//@formaction | descendant-or-self::*[not(self::a)]/@href").each do |attribute|
        next if same_origin?(attribute.value, host)

        attribute.value = "#"
        degrade(:frame_offsite_target, "Replaced a form or link target that points off this site", where:)
      end
      fragment.css("iframe, embed, object").each do |el|
        next if loadable?(el, source(el), host)

        el.remove
        degrade(:frame_offsite_target, "Removed embedded content that points off this site", where:)
      end
      fragment.css("input[src]").each do |el|
        next if same_origin?(el["src"], host)

        el.remove_attribute("src")
        degrade(:frame_offsite_target, "Removed an image button source that points off this site", where:)
      end
      fragment.css("a[href]").each { it["rel"] = "noopener noreferrer" unless same_origin?(it["href"], host) }
    end

    def allow(html, tags, attributes)
      scrubber = StyleScrubber.new
      scrubber.tags = tags
      scrubber.attributes = attributes
      Rails::HTML5::SafeListSanitizer.new.sanitize(html, scrubber:).to_s
    end

    def restyle(el)
      css = style(el["style"])
      css.empty? ? el.remove_attribute("style") : el["style"] = css
    end

    def degrade(kind, reason, where: nil)
      Degradation.record(kind:, where: Degradation.where(where.presence).presence, reason:)
    end
  end
end
