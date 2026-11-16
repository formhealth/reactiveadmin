module ReactiveAdmin
  # The params a form can post, so a write through the API carries only those: disabled fields are dropped, as a
  # browser drops them, and anything no field accounts for is unknown, so `permit_params` can't be reached
  # beyond what the form offers. A has_many row is held to the fields of the saved row its `id` names, or to
  # the new-row template, whatever index the client gave it.
  class FormKeys
    NESTED = /_attributes\](\[#\])?\z/
    LEAF = /\A(.+)\[([^\[\]]+)\]\z/

    def initialize(sections, root)
      fields = sections.flat_map { ParamNormalizer.fields_in(it) }.select { it[:param] }
      @exact = fields.group_by { it[:param].delete_suffix("[]") }
      @shapes = fields.group_by { ParamNormalizer.shape(it[:param].delete_suffix("[]")) }
      @parents = @shapes.keys.flat_map { prefixes(it) }.to_set
      has_many = sections.select { it[:kind] == "has_many" }
      @rows = has_many.to_h { ["#{ParamNormalizer.shape(it[:param])}[#]", it] }
      @destroyable = has_many.select { it[:allow_destroy] }.to_set { "#{ParamNormalizer.shape(it[:param])}[#]" }
      @roots = [root.to_s, *@shapes.keys.map { it[/\A[^\[]+/] }].uniq
    end

    # Drops the params of disabled fields; returns the paths of those no field accounts for.
    def filter!(params)
      @unknown = []
      @roots.each { walk(params, it, it) if params.key?(it) }
      @unknown
    end

    private

    # `row` is [the row's path, its fields by the rest of their param].
    def walk(parent, key, path, row = nil)
      value = parent[key]
      fields = row ? row.last[path.delete_prefix(row.first)] : @exact[path] || @shapes[ParamNormalizer.shape(path)]
      if fields
        parent.delete(key) if fields.all? { it[:disabled] }
      elsif value.is_a?(ActionController::Parameters)
        inner = row_of(path, value) || row
        value.keys.each { walk(value, it, "#{path}[#{it}]", inner) }
      elsif value.is_a?(Array) && value.any? && value.all?(ActionController::Parameters)
        value.each_with_index do |item, index|
          here = "#{path}[#{index}]"
          inner = row_of(here, item) || row
          item.keys.each { walk(item, it, "#{here}[#{it}]", inner) }
        end
      elsif !implicit?(ParamNormalizer.shape(path))
        @unknown << path
      end
    end

    def row_of(path, value)
      section = @rows[ParamNormalizer.shape(path)] or return
      id = value[:id].to_s.presence
      record = section[:records].to_a.find { id && it[:id] == id }
      prefix = record ? record[:param] : "#{section[:param]}[#{FormHasMany::INDEX_PLACEHOLDER}]"
      fields = record ? record[:fields] : section[:template_fields].to_a
      [path, fields.select { it[:param] }.group_by { it[:param].delete_suffix("[]").delete_prefix(prefix) }]
    end

    # Nested attributes name a row by `id`, and remove it by `_destroy` where the section lets rows go.
    def implicit?(shape)
      parent, leaf = shape.match(LEAF)&.captures
      return false unless parent

      (leaf == "id" && parent.match?(NESTED) && @parents.include?(parent)) || (leaf == "_destroy" && @destroyable.include?(parent))
    end

    def prefixes(shape)
      root = shape[/\A[^\[]+/]
      parts = shape.scan(/\[[^\]]*\]/)
      (0...parts.size).map { root + parts.first(it).join }
    end
  end
end
