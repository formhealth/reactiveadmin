module ReactiveAdmin
  # GET and HEAD read, whatever the action does with the request. The one exception is a GET action the host
  # declares with `reactive { unsafe_gets :name }`: it is held to what a write is (write scope, audit, `api :read_only`).
  module ActionSafety
    READ_VERBS = %w[GET HEAD].freeze

    module_function

    def read?(config, name, verb) = READ_VERBS.include?(verb.to_s.upcase) && !unsafe_get?(config, name)

    def unsafe_get?(config, name) = !!config.try(:reactive_options)&.dig(:unsafe_gets)&.include?(name.to_sym)

    # Shell endpoints borrow the root page as their config, so only their verb counts.
    def request_read?(controller)
      config = AA.config_of(controller) unless controller.is_a?(ApiController)
      read?(config, controller.action_name, controller.request.request_method)
    end
  end
end
