module ReactiveAdmin
  # Degradations worth fixing in the host's admin code, collected for a future `doctor` task.
  # Entries name resources, sources and limits only, never record data.
  class Diagnostics
    def initialize
      @entries = Set.new
      @lock = Mutex.new
    end

    def record(kind, **details) = @lock.synchronize { @entries << {kind:, **details} }

    def entries = @lock.synchronize { @entries.to_a }

    def clear = @lock.synchronize { @entries.clear }
  end
end
