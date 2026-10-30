module ReactiveAdmin
  # Arbre content of a `form do |f|` block (headings, panels, tables of the current record) as typed nodes,
  # walked by the same HtmlNodes as a show page. The recorder leaves a marker wherever it records an input;
  # the content before each marker becomes one `content` field in that spot, with the elements still open
  # around an input (a panel holding `f.inputs`) copied into each part they span.
  class FormContent
    CUT = "ra-cut".freeze
    # Containers that carry nothing once the content around an input is split off.
    SHELLS = %w[box panel group].freeze

    def self.marker(id) = %(<#{CUT} data-id="#{id}"></#{CUT}>).html_safe

    def initialize(controller, record)
      @controller = controller
      @record = record
    end

    # The html split at its markers: [[id, html], ...] in order, then what follows the last one under a nil id.
    # Nil when the markup is too deep to split.
    def split(raw)
      fragment = HtmlPolicy.parse(raw) or return
      parts = fragment.css(CUT).map do |marker|
        html = take_before(fragment, marker, marker.ancestors.to_a).map(&:to_html).join
        marker.unlink
        [marker["data-id"], html]
      end
      [*parts, [nil, fragment.to_html]]
    end

    # Nodes for the html, outside any frame: forms and stored markup stay inert, as on a show page.
    def nodes(html)
      return [] if html.blank?

      request = @controller.request
      links = ActionLinks.new(host: request.host, base_url: request.base_url, authorizer: Authorizer.for(@controller), subject: @record)
      tidy(HtmlNodes.nodes(html, host: request.host, links:, resource: Registry.route_key(AA.config_of(@controller))))
    end

    private

    # Moves the nodes before the marker out of the fragment. An ancestor of the marker stays, and its
    # copy takes the part of it that precedes the marker.
    def take_before(parent, marker, chain)
      taken = []
      parent.children.to_a.each do |child|
        break if child == marker

        if chain.include?(child)
          taken << shell(child).tap { |copy| take_before(child, marker, chain).each { copy.add_child(it) } }
          break
        end
        taken << child.unlink
      end
      taken
    end

    # The element and its attributes (a provenance stamp among them) without its children.
    def shell(element)
      Nokogiri::XML::Node.new(element.name, element.document).tap do |copy|
        element.attribute_nodes.each { copy[it.name] = it.value }
      end
    end

    # Drops what an emptied wrapper leaves behind. A panel left with only its title is a heading.
    def tidy(nodes)
      nodes.filter_map do |node|
        next node unless SHELLS.include?(node[:type])

        node = node.merge(children: tidy(node[:children]))
        next node if node[:children].any?

        title(node[:title]) if node[:title].present?
      end
    end

    def title(text) = {type: "heading", level: 3, children: [{type: "text", text:}]}
  end
end
