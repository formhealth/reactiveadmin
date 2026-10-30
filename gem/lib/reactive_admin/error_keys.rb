module ReactiveAdmin
  # Rails keys errors by attribute (`category` for a missing association, `category_id`
  # for its uniqueness), while a client shows one field. Renames each key to the `name` of the field that
  # posts that attribute and merges the messages. Keys inside has_many rows are already `assoc.attr`.
  class ErrorKeys
    def self.call(errors, sections) = new(sections).call(errors)

    def initialize(sections)
      fields = sections.flat_map { (it[:kind] == "has_many") ? [] : it[:fields].to_a }.select { it[:param] }
      @names = fields.to_h { [it[:name], it[:name]] }
      fields.each do |field|
        attribute = field[:param][/\[(\w+)\](?:\[\])?\z/, 1]
        [attribute, field[:name].delete_suffix("_id"), "#{field[:name]}_id"].each { @names[it] ||= field[:name] }
      end
    end

    def call(errors)
      errors.each_with_object({}) do |(key, messages), mapped|
        (mapped[@names.fetch(key.to_s) { key.to_s }] ||= []).concat(messages).uniq!
      end
    end
  end
end
