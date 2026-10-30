module ReactiveAdmin
  # Classic (`/admin/...`) and API paths of a resource's pages. A resource whose `belongs_to`
  # isn't optional is only routed under its parent.
  module Paths
    PARENT_ID = "{parent_id}".freeze

    module_function

    def nested?(config) = config.belongs_to? && config.belongs_to_config.required?

    def api(path) = File.join(ReactiveAdmin.config.mount_path, path)

    # Whether the SPA routes this path itself: under the namespace, and not escaping it with dot segments.
    def admin?(path)
      prefix = "/#{ReactiveAdmin.config.namespace}"
      (path == prefix || path.start_with?("#{prefix}/")) && !path.match?(%r{/\.\.?(/|\z)|%2[ef]}i)
    end

    def collection(config, parent_id: nil)
      parent = config.belongs_to_config.target if parent_id
      ["", ReactiveAdmin.config.namespace, (Registry.route_key(parent) if parent), parent_id, Registry.route_key(config)].compact.join("/")
    end

    def options(config, parent_id: nil) = File.join(collection(config, parent_id:), "_options")

    def lookup(config, parent_id: nil) = File.join(options(config, parent_id:), "lookup")

    def meta(config) = File.join(collection(config), "_meta")

    def labels(config) = File.join(collection(config), "_labels")

    def value(config, parent_id: nil) = File.join(collection(config, parent_id:), ":id", "_value")

    def index_template(config) = (collection(config, parent_id: PARENT_ID) if config.belongs_to?)

    def parent_id(config, params) = (params[config.belongs_to_config.to_param].presence if config.belongs_to?)

    # The params that route `new` under the record's parent, for resources that can be (but needn't be) nested.
    def parent_params(config, record)
      return {} unless config.belongs_to? && record

      fk = record[record.class.reflect_on_association(config.belongs_to_config.target_name).foreign_key]
      fk.present? ? {config.belongs_to_config.to_param => fk.to_s} : {}
    end

    def record(config, record)
      member = member(config, record)
      show = member if Registry.actions(config).include?(:show)
      edit = "#{member}/edit" if Registry.actions(config).include?(:edit)
      {show:, edit:, api_show: (api(show) if show), api_edit: (api(edit) if edit)}.compact
    end

    # Composite keys join their parts, which may hold spaces or slashes.
    def member(config, record) = File.join(collection(config, parent_id: parent_id_of(config, record)), ERB::Util.url_encode(record.to_param.to_s))

    # Read from the foreign key: loading the parent would be an n+1 across index rows.
    def parent_id_of(config, record)
      return unless nested?(config)

      record[record.class.reflect_on_association(config.belongs_to_config.target_name).foreign_key]&.to_s
    end
  end
end
