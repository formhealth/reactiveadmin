module ReactiveAdmin
  # Typed nodes the gem itself emits into rendered HTML (show-row JSON values) travel as opaque
  # ids into a per-request table. Markup can't carry a node: host-rendered HTML may hold user
  # text, and anything it says about a node (a `data-node` attribute, a guessed id) resolves to
  # nothing. Ids are random and die with the scope, so they never resolve in another request.
  module NodeRegistry
    CLASS_NAME = "reactiveadmin-node".freeze
    LEGACY_CLASS_NAME = "reactiveadmin-json".freeze
    ALLOWED_TYPES = %w[json text empty form].freeze
    KEY = :reactiveadmin_node_registry
    STATE = ActiveSupport::IsolatedExecutionState

    module_function

    def with_scope
      previous = STATE[KEY]
      STATE[KEY] = {}
      yield
    ensure
      STATE[KEY] = previous
    end

    # Outside a scope the id resolves to nothing, which is right for renders whose HTML is discarded.
    def register(node)
      type = node[:type].to_s
      raise ArgumentError, "node type #{type.inspect} can't travel through markup" unless ALLOWED_TYPES.include?(type)

      SecureRandom.hex(16).tap { |id| STATE[KEY]&.store(id, node.freeze) }
    end

    def resolve(id) = STATE[KEY]&.[](id.to_s)

    def marker(node) = %(<span class="#{CLASS_NAME}" data-node-id="#{register(node)}"></span>).html_safe

    # The node a marker element stands for, or nil with a degradation when this request never
    # issued it.
    def from_html(el)
      node = resolve(el["data-node-id"]) if el.classes.include?(CLASS_NAME)
      return node if node

      Degradation.record(kind: :forged_node_marker, where: Degradation.where, reason: "Markup claimed to be a typed node; dropped")
      nil
    end

    def marker?(el) = (el.classes & [CLASS_NAME, LEGACY_CLASS_NAME]).any?
  end
end
