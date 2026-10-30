module ReactiveAdmin
  # Images and PDFs the HTML policy lets load, as typed nodes the client shows with a lightbox or viewer. What
  # this doesn't take (data: images, other embeds, off-site media) stays with HtmlPolicy's html and link rules.
  module MediaNodes
    MAX_DIMENSION = 10_000

    module_function

    def for(el, host:)
      src = HtmlPolicy.source(el)
      return unless web_url?(src) && HtmlPolicy.same_origin?(src, host)

      (el.name == "img") ? image(el, src) : document(el, src)
    end

    def image(el, src)
      {type: "image", src:, alt: el["alt"].to_s.strip, width_px: dimension(el["width"]), height_px: dimension(el["height"])}.compact
    end

    def document(el, src)
      return unless (el.name == "iframe") ? HtmlPolicy.pdf_path?(src) : HtmlPolicy.pdf?(el, src)

      {type: "document", src:, mime: "application/pdf", title: el["title"].to_s.strip.presence}.compact
    end

    # A relative path is the request's own site; a scheme must be http(s). Never data: or protocol-relative.
    def web_url?(src) = src.match?(%r{\Ahttps?://}i) || (src.start_with?("/") && !src.start_with?("//"))

    def dimension(value)
      size = Integer(value.to_s.strip, 10, exception: false)
      size if size&.between?(1, MAX_DIMENSION)
    end
  end
end
