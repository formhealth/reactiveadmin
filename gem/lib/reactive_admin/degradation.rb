module ReactiveAdmin
  # What a request fell back to instead of failing: a block that raised, markup shown as html,
  # a sidebar dropped. Collected per request, attached to the response as `degraded`, and
  # published as `degraded.reactiveadmin` notifications for metrics. Entries carry structural
  # paths and exception classes only, never record data or exception messages.
  module Degradation
    EVENT = "degraded.reactiveadmin".freeze
    HEADER = "X-Reactiveadmin-Degraded".freeze
    KEY = :reactiveadmin_degradation
    STATE = ActiveSupport::IsolatedExecutionState

    Collector = Struct.new(:resource, :route_key, :action, :entries, :tallies, :controller)

    module_function

    # Outside a collection (the manifest, a console) the notification still fires.
    def record(kind:, reason:, where: nil)
      collector = STATE[KEY]
      entry = {kind: kind.to_s, where:, reason:}.compact
      instrument(entry, collector) if collector.nil? || collector.entries.add?(entry)
      nil
    end

    # Repeats within a response collapse into one entry; `reason` takes the count as `%d`.
    def tally(kind:, reason:, where: nil)
      collector = STATE[KEY] or return
      (collector.tallies[kind.to_s] ||= {where:, reason:, count: 0})[:count] += 1
    end

    def entries
      collector = STATE[KEY] or return []
      collector.entries.to_a + collector.tallies.map { |kind, t| {kind:, where: t[:where], reason: format(t[:reason], t[:count])}.compact }
    end

    # Structural location under the current action, e.g. `show/div[0]/ul[1]`.
    def where(*steps) = [STATE[KEY]&.action, *steps].compact.join("/")

    # `controller` is the request's own, so the audit envelope can be joined to it (channel, client id, request and correlation ids).
    def with_collection(resource: nil, action: nil, controller: nil)
      previous = STATE[KEY]
      route_key = resource.respond_to?(:route_key) ? resource.route_key : resource&.to_s
      collector = STATE[KEY] = Collector.new(resource&.to_s, route_key, action&.to_s, Set.new, {}, controller)
      yield.tap { collector.tallies.each { |kind, t| instrument({kind:, where: t[:where]}, collector) } }
    ensure
      STATE[KEY] = previous
    end

    def attach(payload)
      list = entries
      list.empty? ? payload : payload.merge(degraded: list)
    end

    def instrument(entry, collector)
      payload = {resource: collector&.resource, action: collector&.action, **entry.slice(:kind, :where)}
      Audit.instrument("degraded", collector&.controller, payload, payload.merge(resource: collector&.route_key, user_id: nil))
    end
  end
end
