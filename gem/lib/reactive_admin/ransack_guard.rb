module ReactiveAdmin
  # Ransack accepts any attribute, association and predicate a model exposes, which turns `q` into
  # a way to probe columns the page never shows. On the API only the predicates of the resource's
  # declared filters are honoured; anything else is rejected rather than silently dropped, so a
  # client bug surfaces. AA sorts and scopes through `order` and `scope`, so `q` carries nothing else.
  #
  # Every action is guarded, because any of them may reach AA's `collection` with the raw `q`. The
  # exceptions are actions whose `q` is their own search form: declared by the host
  # (`reactive { own_query_params :search }` or `config.ransack_unguarded_actions`), or learned
  # from a recorded template form that posts `q[...]` fields to them (see `learn`).
  module RansackGuard
    MAX_KEY_LENGTH = 100
    LEARNED_KEY = "reactiveadmin:q_owner:%s#%s".freeze

    def self.own_query?(config, controller_path, action)
      action = action.to_s
      declared = [*config.try(:reactive_options)&.dig(:own_query_params), *host_declared(config)]
      declared.any? { it.to_s == action } || learned.include?([controller_path, action]) ||
        Rails.cache.exist?(format(LEARNED_KEY, controller_path, action))
    end

    def self.host_declared(config)
      Array((ReactiveAdmin.config.ransack_unguarded_actions || {}).with_indifferent_access[Registry.route_key(config)])
    end

    def self.learned = (@learned ||= Concurrent::Set.new)

    # Actions that recorded template forms post `q[...]` fields to: their `q` is a search form's.
    # Kept per process and on the shared cache, so another process serving the submit agrees.
    def self.learn(forms)
      forms.each do |form|
        next unless Array(form[:items]).flat_map { fields_of(it) }.any? { it[:param].to_s.start_with?("q[") }

        route = Rails.application.routes.recognize_path(form[:path].to_s, method: form[:method])
        learned << [route[:controller], route[:action]]
        Rails.cache.write(format(LEARNED_KEY, route[:controller], route[:action]), true)
      rescue ActionController::RoutingError
        next
      end
    end

    def self.fields_of(item)
      case item
      in [:field, Hash => field] then [field]
      in [:section, Hash => section] then section[:fields]
      in [:group, Array => list] then list.flat_map { fields_of(it) }
      else []
      end
    end

    # Search names a declared filter can produce, without predicate: the attribute itself and the
    # names AA's association inputs search on (`post_id`, or the foreign key of a has_many through).
    def self.bases(config)
      klass = config.resource_class
      AA.filters(config).keys.flat_map do |attr|
        name = attr.to_s
        reflection = klass.reflect_on_association(name)
        next [name] unless reflection

        [name, "#{name}_#{reflection.association_primary_key}", reflection.foreign_key.to_s,
          ("#{reflection.through_reflection.name}_#{reflection.foreign_key}" if reflection.through_reflection)].compact
      rescue
        [name]
      end.to_set
    end

    def self.allowed?(bases, key)
      return true if bases.include?(key)

      stripped = key.dup
      Ransack::Predicate.detect_and_strip_from_string!(stripped) && bases.include?(stripped)
    end

    # The first key that no declared filter explains, or nil.
    def self.violation(config, query)
      return "q" unless query.respond_to?(:keys)

      bases = bases(config)
      query.keys.map(&:to_s).find { !allowed?(bases, it) }
    end

    private

    # Overridden as ControllerExtension does: callbacks registered on AA's base class are not
    # inherited by controllers that were already built.
    def authenticate_active_admin_user
      super
      reject_undeclared_filters unless performed?
    end

    def reject_undeclared_filters
      return unless reactiveadmin_request? && params.key?(:q)
      return if RansackGuard.own_query?(active_admin_config, controller_path, action_name)

      key = RansackGuard.violation(active_admin_config, params[:q])
      render_api_error(:invalid, "Unsupported filter: #{key.truncate(MAX_KEY_LENGTH)}", 400) if key
    end
  end
end
