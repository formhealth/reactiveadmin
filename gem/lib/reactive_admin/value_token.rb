module ReactiveAdmin
  # The signed proof an `expand_path` carries: this server rendered `field` of this record for this
  # user, on index, show or the edit form. `_value` checks the proof instead of re-rendering a page to
  # find out what the field may expose; the caller's permission on the record is still checked per request.
  module ValueToken
    PURPOSE = "reactiveadmin_value".freeze
    VIAS = %w[index show form].freeze

    module_function

    def mint(controller, config, record, field, via)
      verifier.generate(
        {"r" => Registry.route_key(config), "i" => record.to_param.to_s, "f" => field.to_s, "u" => user_id(controller), "v" => via},
        purpose: PURPOSE, expires_in: ReactiveAdmin.config.value_token_ttl
      )
    end

    # The page the token was minted for (index, show or form), or nil when it is missing, forged,
    # expired or was issued for another user, record or field.
    def verify(controller, config, record, field, token)
      claims = verifier.verified(token.to_s, purpose: PURPOSE) if token.is_a?(String)
      return unless claims.is_a?(Hash) && VIAS.include?(claims["v"])

      expected = {"r" => Registry.route_key(config), "i" => record.to_param.to_s, "f" => field.to_s, "u" => user_id(controller)}
      claims["v"] if expected.all? { |key, value| claims[key] == value }
    end

    def verifier = Rails.application.message_verifier(PURPOSE)

    # Hosts derive the user from queries, so it is asked once per request.
    def user_id(controller)
      controller.instance_variable_get(:@reactiveadmin_token_user) ||
        controller.instance_variable_set(:@reactiveadmin_token_user, ReactiveAdmin.current_user(controller)&.id.to_s)
    end
  end
end
