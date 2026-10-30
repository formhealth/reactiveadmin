module ReactiveAdmin
  # Gives submitted params the shape a browser's post of the classic form would have, so every client
  # behaves like classic whatever it sends for a blank or structured value. Only params that match a
  # field of the form are touched, and each is judged by that field's declared control.
  class ParamNormalizer
    # Browsers have no blank for these: a checkbox is on or off, a file is chosen or not, a multi-select
    # holds a list.
    KEPT = %w[boolean file html multiselect checkboxes].freeze
    ROW = /\[(?:\d+|__INDEX__)\]/

    # `permitted` returns the host's strong parameters for the request.
    def self.call(params, sections, permitted: nil) = new(sections, permitted).call(params)

    def initialize(sections, permitted)
      @permitted = permitted
      fields = sections.flat_map { fields_in(it) }.select { it[:param] }
      @controls = fields.to_h { [shape(it[:param].delete_suffix("[]")), it[:control]] }
      @summarized = fields.select { it[:summary] }.to_set { shape(it[:param]) }
    end

    # An unselected radio posts nothing; any other blank control posts an empty string.
    def call(node, path = [])
      node.keys.each do |name|
        here = [*path, name]
        control = @controls[shape(bracketed(here))]
        value = node[name]
        if control == "json" then json(node, name, value, here, @summarized.include?(shape(bracketed(here))))
        elsif value.is_a?(ActionController::Parameters) then call(value, here)
        elsif control == "radio" then node.delete(name) if value.nil? || value == ""
        elsif value.nil? && control && !KEPT.include?(control) then node[name] = ""
        end
      end
    end

    private

    def fields_in(section)
      return section[:fields] || [] unless section[:kind] == "has_many"

      [*section[:records].to_a.flat_map { it[:fields] }, *section[:template_fields]]
    end

    # `a[b][3][c]` and `a[b][__INDEX__][c]` are the same field in different rows.
    def shape(param) = param.gsub(ROW, "[#]")

    def bracketed(path) = path.first + path.drop(1).map { "[#{it}]" }.join

    # A textarea posts JSON text, which a host takes as a scalar `permit_params` attribute and parses.
    # A host that permits `attr: {}` wants the structure, so it keeps it. A summarized field was never
    # sent its value, so blank means the client didn't load it: the stored value stays.
    def json(node, name, value, path, summarized)
      if summarized && (value.nil? || value == "") then node.delete(name)
      elsif value.nil? then node[name] = ""
      elsif !value.is_a?(String) && !structure_permitted?(path) then node[name] = JSON.generate(plain(value))
      end
    end

    def structure_permitted?(path)
      @allowed = @permitted&.call unless defined?(@allowed)
      !@allowed&.dig(*path).nil?
    rescue
      false
    end

    def plain(value)
      case value
      when ActionController::Parameters then value.to_unsafe_h.transform_values { plain(it) }
      when Array then value.map { plain(it) }
      else value
      end
    end
  end
end
