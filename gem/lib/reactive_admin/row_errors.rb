module ReactiveAdmin
  # Rails keys a has_many row's errors by `assoc.attribute` alone, so a list can't tell which row failed.
  # This names the rows: a saved one by its id, a new one by its place among the new rows, which is the order
  # the client sent them in.
  class RowErrors
    def self.call(record, associations) = new(record).call(associations.to_a).presence

    def initialize(record)
      @record = record
    end

    def call(associations)
      associations.to_h { [it.to_s, rows(it)] }.reject { _2.empty? }
    end

    private

    def rows(assoc)
      fresh = 0
      @record.association(assoc).target.filter_map do |child|
        position = fresh unless child.persisted?
        fresh += 1 unless child.persisted?
        next if child.marked_for_destruction? || child.errors.empty?

        {id: (child.to_param.to_s if child.persisted?), new: position, errors: child.errors.to_hash}.compact
      end
    end
  end
end
