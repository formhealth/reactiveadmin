module ReactiveAdmin
  # Maps AA authorization (action + subject) to the contract's Permissions object.
  # Keys for actions the resource doesn't define are omitted rather than false. `create` and
  # `update` answer the NEW and EDIT checks behind classic AA's buttons; writes still authorize
  # CREATE and UPDATE.
  class Permissions
    CHECKS = {
      index: [AA::Auth::READ, %i[index]],
      show: [AA::Auth::READ, %i[show]],
      create: [AA::Auth::NEW, %i[new create]],
      update: [AA::Auth::EDIT, %i[edit update]],
      destroy: [AA::Auth::DESTROY, %i[destroy]]
    }.freeze

    def initialize(config, authorizer)
      @config = config
      @authorizer = authorizer
    end

    def resource = build(@config.resource_class, CHECKS, Registry.top_level_actions(@config))

    def record(record) = build(record, CHECKS.slice(:show, :update, :destroy))

    private

    def build(subject, checks, defined = Registry.actions(@config))
      checks.select { |_, (_, actions)| defined.intersect?(actions) }
        .transform_values { |(action, _)| @authorizer.authorized?(action, subject, config: @config) }
    end
  end
end
