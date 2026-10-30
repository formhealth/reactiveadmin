module ReactiveAdmin
  # Snapshot and restore for process-wide state. Only specs load this, so the production classes
  # can't be rewound at runtime.
  module TestSupport
    module_function

    # Collections are copied so in-place edits (`masked_attributes << ...`) are undone too.
    def snapshot_config(config)
      config.instance_variables.to_h { [it, copy(config.instance_variable_get(it))] }
    end

    def restore_config(config, snapshot)
      snapshot.each { |name, value| config.instance_variable_set(name, copy(value)) }
    end

    def snapshot_sources(sources) = sources.instance_variable_get(:@sources).dup

    def restore_sources(sources, snapshot) = sources.instance_variable_set(:@sources, snapshot.dup)

    # Bumps the version so anything cached against the overlay is recomputed.
    def snapshot_overlay(overlay = MenuOverlay) = overlay.entries.dup

    def restore_overlay(snapshot, overlay = MenuOverlay)
      overlay.instance_variable_set(:@entries, snapshot.dup)
      overlay.instance_variable_set(:@version, overlay.version + 1)
      overlay.instance_variable_set(:@audit, nil)
    end

    def copy(value) = value.is_a?(Enumerable) ? value.dup : value
  end
end
