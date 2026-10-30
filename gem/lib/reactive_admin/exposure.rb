module ReactiveAdmin
  # With `config.expose = :listed` the API serves only what the host names: resources and pages
  # placed in the menu overlay, keys in `config.exposed_resources`, and anything marked
  # `reactive { expose true }`. Everything else answers 404 whatever the authorization policy says.
  # A nested-only resource also needs its parent to be exposed. `reactive { expose false }` denies
  # outright. Classic ActiveAdmin is unaffected.
  module Exposure
    # Prepended to AA's controllers so every API endpoint is covered in one place: after
    # authentication (signed-out clients learn nothing) and before any authorization.
    module Guard
      private

      def authenticate_active_admin_user
        super
        return if performed? || !reactiveadmin_request?
        return if Exposure.allowed?(active_admin_config)

        render_api_error(:not_found, "Not found", 404)
      end
    end

    module_function

    def listed? = ReactiveAdmin.config.expose == :listed

    # `config` is an ActiveAdmin resource or page.
    def allowed?(config)
      return true unless listed?

      explicit = config.reactive_options[:expose]
      return false if explicit == false
      return false unless explicit || listed_keys(config).include?(key(config))

      !Paths.nested?(config) || allowed?(config.belongs_to_config.target)
    end

    def key(config) = page?(config) ? Menu.page_key(config) : Registry.route_key(config)

    # Findings for `doctor`: listed keys that match nothing and, given a user, what the policy
    # permits but the host has not exposed.
    def audit(user: nil) = [*unknown_keys, *permitted_not_exposed(user)]

    def page?(config) = AA.page?(config)

    # Rebuilt when the overlay, the registrations or the configured list change.
    def listed_keys(config)
      stamp = [MenuOverlay.version, Registry.index.object_id, listed_config]
      @listed = nil unless @stamp == stamp
      @stamp = stamp
      @listed ||= {
        resource: Set.new([*MenuOverlay.keys(:resource), *placed_by_hint, *listed_config]),
        page: Set.new([*MenuOverlay.keys(:page), *listed_config, *root_page_key])
      }
      @listed.fetch(page?(config) ? :page : :resource)
    end

    # The namespace's home (`root_to`) is where the shell lands, menu or not.
    def root_page_key = AA.root_page_key(Registry.namespace)

    def listed_config = Array(ReactiveAdmin.config.exposed_resources).map(&:to_s)

    def placed_by_hint
      Registry.resources.filter_map { Registry.route_key(it) if it.reactive_options[:menu]&.key?(:path) }
    end

    def unknown_keys
      known = [*Registry.resources, *Registry.pages].map { key(it) }
      (listed_config - known).map { {kind: :exposure_unknown_key, key: it} }
    end

    def permitted_not_exposed(user)
      return [] unless listed? && user

      authorizer = Authorizer.new(user)
      candidates = [*Registry.resources.select { Registry.actions(it).include?(:index) }, *Registry.pages]
      keys = candidates.reject { allowed?(it) || ApiGuards.fully_denied?(it) }.select { permitted?(authorizer, it) }.map { key(it) }.sort
      keys.empty? ? [] : [{kind: :exposure_permitted_not_exposed, keys: keys.join(", ")}]
    end

    def permitted?(authorizer, config)
      authorizer.authorized?(AA::Auth::READ, page?(config) ? config : config.resource_class, config:)
    rescue
      false
    end
  end
end
