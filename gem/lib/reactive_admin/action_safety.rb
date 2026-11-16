module ReactiveAdmin
  # Which requests only read. A GET custom action reads when it renders a page (Ladder finds its view) or the
  # host vouches for it with `reactive { safe_gets :name }`; any other GET action redirects or sends data,
  # so it acted, and it is held to what a write is: the write scope, the write audit, `api :read_only`.
  module ActionSafety
    READ_VERBS = %w[GET HEAD].freeze

    module_function

    def read?(config, name, verb)
      return false unless READ_VERBS.include?(verb.to_s.upcase)

      !Ladder.declared?(config, name) || safe_get?(config, name)
    end

    def safe_get?(config, name)
      config.try(:reactive_options)&.dig(:safe_gets)&.include?(name.to_sym) || !Ladder.action(config, name).nil?
    end

    # GET custom actions treated as writes.
    def unsafe_gets(config)
      AA.custom_actions(config).filter_map do |declaration|
        name = declaration.name.to_s
        name if Array.wrap(declaration.http_verb).any? { it.to_s.casecmp?("get") } && !safe_get?(config, name)
      end
    end

    def audit
      [*Registry.resources, *Registry.pages].flat_map do |config|
        unsafe_gets(config).map do |name|
          {kind: :get_action_write, resource: Exposure.key(config), action: name,
           reason: "GET action #{name} renders no page, so the API treats it as a write; list it in `reactive { safe_gets :#{name} }` if it only reads"}
        end
      end
    end
  end
end
