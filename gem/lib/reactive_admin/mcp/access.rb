module ReactiveAdmin
  module Mcp
    # How much of a resource or page agents get: `config.mcp.default`, or `reactive { mcp ... }` in its
    # registration. A mode reads as one more `api` guard on MCP requests, so it narrows what the guards
    # leave open and never widens it.
    #
    #   :none       left out of MCP: not listed, every tool answers as for an unknown resource
    #   :read_only  reads only; `actions:` adds custom or batch actions agents may run
    #   :full       everything the api guards and the policy allow
    module Access
      MODES = %i[none read_only full].freeze
      REASONS = {none: "Not available to agents", read_only: "Agents only read this"}.freeze
      # What each resource tool exercises, for the doctor.
      TOOLS = {"list_records" => %w[index], "get_record" => %w[show], "get_form" => %w[new edit],
               "create_record" => %w[create], "update_record" => %w[update], "delete_record" => %w[destroy]}.freeze

      module_function

      def declare(config, mode = nil, actions: nil)
        raise ArgumentError, "mcp needs a mode: #{MODES.map(&:inspect).join(", ")}" if mode.nil? && actions.nil?

        mode = (mode || :read_only).to_sym
        raise ArgumentError, "mcp #{mode.inspect}: expected one of #{MODES.map(&:inspect).join(", ")}" unless MODES.include?(mode)
        raise ArgumentError, "mcp #{mode.inspect} takes no actions: they only add to :read_only" if actions && mode != :read_only

        config.reactive_options[:mcp] = {mode:, actions: Array(actions).flatten.map(&:to_s)}
      end

      def mode(config) = config.try(:reactive_options)&.dig(:mcp, :mode) || ReactiveAdmin.config.mcp.default

      def listed(config) = config.try(:reactive_options)&.dig(:mcp, :actions) || []

      def visible?(config) = mode(config) != :none

      # The guard the mode amounts to, nil for :full. A read-only one leaves the listed custom and batch actions out of its reach.
      def declaration(config)
        case mode(config)
        when :none then ApiGuards::Declaration.new(guard: :deny, only: nil, except: nil, attributes: nil, reason: REASONS[:none])
        when :read_only then ApiGuards::Declaration.new(guard: :read_only, only: nil, except: nil, attributes: nil, reason: REASONS[:read_only], exempt: listed(config).presence)
        end
      end

      # The mode alone, not the api guards: what it refuses answers as unknown, what a guard refuses names the guard.
      def allows?(config, names, verb: nil)
        declaration = declaration(config) or return true
        names = names.map(&:to_s)
        !(ApiGuards.applies?(declaration, names) && ApiGuards.refuses_statically?(declaration, config, names, verb:, channel: :mcp))
      end

      # Whether the mode lets a call through for at least one of these verbs; with none, as for any verb.
      def allows_any?(config, names, verbs) = verbs.empty? ? allows?(config, names) : verbs.any? { allows?(config, names, verb: it) }

      def offers?(config, name) = Registry.actions(config).include?(name.to_sym) && allows?(config, [name])

      # Custom and batch actions the mode lets run_action reach.
      def runnable(config)
        [*AA.custom_actions(config).select { allows_any?(config, [it.name.to_s], verbs_of(it)) }.map { it.name.to_s },
          *AA.batch_actions(config).map { it.sym.to_s }.select { allows?(config, ["batch_action", it]) }].uniq
      end

      def verbs_of(action) = Array.wrap(action.http_verb).map { it.to_s.upcase }

      # Whether any resource offers one of these actions, so a tool no resource offers stays out of tools/list.
      def anywhere?(*names) = Registry.resources.any? { |config| names.any? { offers?(config, it) } }

      def any_runnable? = Registry.resources.any? { runnable(it).any? }

      def any_visible?(configs) = configs.any? { visible?(it) }

      # What agents reach of each served resource and page, after the api guards, for the doctor.
      def surface
        [*Registry.resources, *Registry.pages].select { Exposure.allowed?(it) }.map do |config|
          page = AA.page?(config)
          tools, actions = open_to_agents(config, page)
          {key: Exposure.key(config), kind: page ? "page" : "resource", mode: mode(config).to_s, tools:, actions:}
        end
      end

      def open_to_agents(config, page)
        return [[], []] if ApiGuards.whole?(config, channel: :mcp)

        open = ->(*names) { !ApiGuards.denial(config, names, channel: :mcp) }
        open_verb = ->(action) { verbs_of(action).any? { !ApiGuards.denial(config, [action.name.to_s], verb: it, channel: :mcp) } }
        actions = page ? [] : [*AA.custom_actions(config).select { open_verb.call(it) }.map { it.name.to_s },
          *AA.batch_actions(config).map { it.sym.to_s }.select { open.call("batch_action", it) }].uniq
        tools = if page
          open.call("index") ? %w[get_page] : []
        else
          TOOLS.select { |_, names| names.any? { Registry.actions(config).include?(it.to_sym) && open.call(it) } }.keys
        end
        tools << "run_action" if actions.any?
        [tools, actions]
      end

      def sensitive?(config) = !AA.page?(config) && (LookupAudit.sensitive_resource?(config) || masked?(config))

      def masked?(config) = config.reactive_options[:mask].present? || config.resource_class.column_names.any? { Masking.attribute?(it, config) }

      # :full on a resource whose names or attributes the host already treats as sensitive.
      def audit
        return [] unless ReactiveAdmin.config.mcp.possibly_enabled?

        Registry.resources.select { mode(it) == :full && Exposure.allowed?(it) && sensitive?(it) }.map do |config|
          key = Exposure.key(config)
          {kind: :mcp_full_sensitive, resource: key,
           reason: "#{key} is mcp :full but is sensitive or masks attributes: agents may write it; prefer :read_only and list the actions they need"}
        end
      end
    end
  end
end
