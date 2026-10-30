module ReactiveAdmin
  # Rich-text HTML as typed nodes: headings, paragraphs with inline marks, rules, quotes, disclosures,
  # lists and definition lists. Mixed into HtmlNodes, which owns the walk and the sanitized fallback.
  module HtmlRich
    MARKS = {
      "b" => "strong", "strong" => "strong", "i" => "em", "em" => "em", "u" => "underline", "ins" => "underline",
      "s" => "strike", "strike" => "strike", "del" => "strike", "code" => "code", "kbd" => "code", "samp" => "code",
      "mark" => "mark", "small" => "small", "sub" => "sub", "sup" => "sup"
    }.freeze
    HEADINGS = %w[h1 h2 h3 h4 h5 h6].freeze
    BLOCKS = (HEADINGS + %w[hr dl blockquote details ul ol li]).freeze
    SPACE = /[ \t\r\n\f]+/

    private

    # A lone `<code>` is a code node, and a `<p>` with plain text or layout classes is a text or box node.
    def rich?(el)
      case el.name
      when "p" then el.element_children.any? && layout_hints(el).empty?
      when "code" then false
      else BLOCKS.include?(el.name) || MARKS.key?(el.name) || el.name == "abbr"
      end
    end

    def rich(el)
      if el.name == "hr" then {type: "divider"}
      elsif HEADINGS.include?(el.name) then inline_container("heading", el, level: el.name[1].to_i)
      elsif el.name == "p" then inline_container("paragraph", el)
      elsif el.name == "blockquote" then {type: "blockquote", children: nodes(el.inner_html)}
      elsif el.name == "details" then disclosure(el)
      elsif el.name == "dl" then definition_list(el)
      elsif el.name == "li" then list(false, [[el, 0]])
      elsif %w[ul ol].include?(el.name) then list(el.name == "ol", el.children.each_with_index.to_a)
      else run([[el, 0]])
      end
    end

    def inline_container(type, el, **attrs)
      children = tidy(inline(el.children.each_with_index.to_a))
      {type:, **attrs, children:} if children.any?
    end

    def disclosure(el)
      summary = el.element_children.find { it.name == "summary" }
      title = summary ? tidy(inline(summary.children.each_with_index.to_a)) : []
      body = el.children.reject { it == summary }
      {type: "disclosure", summary_nodes: title.presence || [{type: "text", text: "Details"}], open: el.key?("open"), children: nodes(body.map(&:to_html).join)}
    end

    def definition_list(el)
      rows = []
      each_term_or_detail(el) do |child|
        rows << {label: "", value: []} if rows.empty? || child.name == "dt"
        (child.name == "dt") ? rows.last[:label] = child.text.squish : rows.last[:value].concat(nodes(child.inner_html))
      end
      return if rows.empty?

      {type: "definition_list", rows: rows.map { it.merge(value: it[:value].presence || [{type: "empty"}]) }}
    end

    def each_term_or_detail(el, &)
      el.element_children.each do |child|
        (child.name == "div") ? each_term_or_detail(child, &) : (yield child if %w[dt dd].include?(child.name))
      end
    end

    # Anything under ul/ol becomes an item, so stray non-li children still render.
    def list(ordered, children)
      items = children.filter_map do |child, index|
        next if child.comment? || (child.text? && child.text.strip.empty?)

        at("#{child.name}[#{index}]") do
          content = (child.name == "li") ? nodes(child.inner_html) : [node(child)].compact
          {type: "list_item", children: content}
        end
      end
      {type: "list", ordered:, children: items}
    end

    # Siblings in document order. Inline runs that carry formatting become paragraphs; loose `li`s are gathered into
    # a list; everything else is walked one node at a time.
    def siblings(children)
      groups(children.each_with_index.reject { |el, _| el.comment? }).flat_map do |kind, items|
        case kind
        when :run then run(items)
        when :li then list(false, items)
        else at("#{items.first.first.name}[#{items.first.last}]") { node(items.first.first) }
        end
      end.compact
    end

    def groups(items)
      items.each_with_object([]) do |item, groups|
        el = item.first
        kind = if el.text? && el.text.strip.empty? then :blank
        elsif el.element? && el.name == "li" then :li
        elsif inline?(el) then :run
        else :other
        end
        last = groups.last
        if kind == :blank
          last&.last&.push(item) if last&.first&.in?(%i[run li])
        elsif last && last.first == kind && kind != :other
          last.last << item
        else
          groups << [kind, [item]]
        end
      end
    end

    def inline?(el)
      return true if el.text? || el.cdata?
      return false unless el.element?

      MARKS.key?(el.name) || %w[abbr br].include?(el.name) || (el.name == "a" && !ActionLinks.control?(el)) ||
        (el.name == "span" && el["class"].blank? && el["style"].blank? && !ActionLinks.control?(el))
    end

    # A run with no formatting keeps the plain per-node output. A lone `<code>` stays a code node.
    def run(items)
      tags = items.map(&:first).select(&:element?).map(&:name)
      surrounded = items.any? { |el, _| el.text? ? el.text.strip.present? : el.element? && el.name != "code" }
      formatted = tags.any? { (MARKS.key?(it) && it != "code") || it == "abbr" } || (tags.include?("code") && surrounded)
      return items.filter_map { |el, index| at("#{el.name}[#{index}]") { node(el) } } unless formatted

      list = tidy(inline(items))
      (list.size == 1 && list.first[:type] == "text") ? list : [paragraph(list)].compact
    end

    def paragraph(children) = ({type: "paragraph", children:} if children.any?)

    def inline(items, marks: [], title: nil)
      items.flat_map do |el, index|
        if el.text? || el.cdata? then segment(el.text, marks, title)
        elsif !el.element? then []
        elsif el.name == "br" then [{type: "break"}]
        elsif MARKS.key?(el.name) then inline(indexed(el), marks: (marks + [MARKS[el.name]]).uniq, title:)
        elsif el.name == "abbr" then inline(indexed(el), marks:, title: el["title"].presence || title)
        elsif el.name == "span" && el["class"].blank? && el["style"].blank? then inline(indexed(el), marks:, title:)
        else
          typed = at("#{el.name}[#{index}]") { node(el) }
          (typed && typed[:type] == "text" && marks.any?) ? [typed.merge(marks:)] : [typed].compact
        end
      end
    end

    def indexed(el) = el.children.each_with_index.to_a

    def segment(string, marks, title)
      string = string.gsub(SPACE, " ")
      string.empty? ? [] : [{type: "text", text: string, marks: marks.presence, title:}.compact]
    end

    # Spacing inside a run collapses like HTML's: no leading, trailing or doubled spaces, none around a break.
    def tidy(list)
      space = true
      list.each_with_object([]) do |node, out|
        if node[:type] == "text"
          text = space ? node[:text].delete_prefix(" ") : node[:text]
          next if text.empty?

          space = text.end_with?(" ")
          node = node.merge(text:)
          last = out.last
          if last && last[:type] == "text" && last.except(:text) == node.except(:text)
            out[-1] = last.merge(text: last[:text] + text)
          else
            out << node
          end
        else
          trim_end(out) if node[:type] == "break"
          space = node[:type] == "break"
          out << node
        end
      end.tap { trim_end(it) }
    end

    def trim_end(out)
      last = out.last
      return unless last && last[:type] == "text" && last[:text].end_with?(" ")

      trimmed = last[:text].chomp(" ")
      trimmed.empty? ? out.pop : out[-1] = last.merge(text: trimmed)
    end
  end
end
