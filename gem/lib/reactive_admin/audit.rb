module ReactiveAdmin
  # One `audit.reactiveadmin` event for everything the per-kind events report, in one shape, plus record views
  # (`config.audit_views`) and UI switches. Every field is an id or a name, never a value.
  module Audit
    EVENT = "audit.reactiveadmin".freeze
    KINDS = %w[write write_rejected export value_viewed lookup mcp_call degraded view ui_switch].freeze
    # Set by Mcp::Api on the requests a tool call makes (a client header arrives as HTTP_*), so its writes join the call.
    CORRELATION_ENV = "reactiveadmin.correlation_id".freeze
    ENVELOPE_KEYS = %i[user_id resource action id record_ids client_id status].freeze
    OUTCOMES = {"write_rejected" => "rejected", "degraded" => "degraded"}.freeze

    Event = Data.define(:kind, :user_id, :resource, :action, :record_ids, :channel, :client_id, :request_id, :correlation_id, :outcome, :at, :details)

    module_function

    # Publishes the per-kind event exactly as before, then the envelope, even if a legacy subscriber raises.
    # `envelope` is what the envelope reads, when it differs from the legacy payload.
    def instrument(kind, controller, payload, envelope = payload)
      ActiveSupport::Notifications.instrument("#{kind}.reactiveadmin", payload)
    ensure
      publish(kind, controller, **envelope)
    end

    # Never raises: whatever is being audited has already happened.
    def publish(kind, controller = nil, **fields)
      ActiveSupport::Notifications.instrument(EVENT, snapshot(build(kind.to_s, controller, fields).to_h))
    rescue => e
      Rails.logger.error("[reactiveadmin] audit envelope failed: #{e.class}")
    end

    def build(kind, controller, fields)
      request = controller&.request
      Event.new(
        kind:,
        user_id: fields.fetch(:user_id) { ReactiveAdmin.current_user(controller)&.id if controller },
        resource: fields[:resource]&.to_s,
        action: fields.fetch(:action) { controller&.action_name }&.to_s,
        record_ids: Array(fields[:record_ids] || fields[:id]).compact.map(&:to_s),
        channel: request && channel(request),
        client_id: request&.env&.dig(Auth::IDENTITY_ENV)&.client_id,
        request_id: request&.request_id,
        correlation_id: request && (request.env[CORRELATION_ENV] || request.request_id),
        outcome: OUTCOMES.fetch(kind) { fields[:status] || "ok" },
        at: Time.current,
        # Both lookup and degraded payloads name their own sub-kind `kind`.
        details: fields.except(*ENVELOPE_KEYS).compact.transform_keys(kind: :type)
      )
    end

    # A deep frozen copy, so subscribers can't alter each other's events or the producer's objects.
    def snapshot(value)
      case value
      when Hash then value.to_h { |k, v| [k, snapshot(v)] }.freeze
      when Array then value.map { snapshot(it) }.freeze
      else value.frozen? ? value : value.dup.freeze
      end
    end

    def channel(request)
      return "mcp" if request.env.key?(CORRELATION_ENV) || request.path_parameters[:controller] == "reactive_admin/mcp"

      request.env[Auth::IDENTITY_ENV] ? "token" : "session"
    end

    # Subscribes `block` to the envelope; returns the subscriber, for ActiveSupport::Notifications.unsubscribe.
    def subscribe(&block)
      raise ArgumentError, "on_audit needs a block" unless block

      ActiveSupport::Notifications.subscribe(EVENT) { |*, payload| block.call(Event.new(**payload)) }
    end
  end
end
