module ReactiveAdmin
  # `reactive do ... end` inside ActiveAdmin.register: hints for the API that classic ignores.
  module ResourceDSL
    def reactive(&) = ReactiveDSL.new(config).instance_eval(&)

    # What the API refuses, whoever asks, while the classic admin is unaffected; see ApiGuards.
    #
    #   api false                                   # everything
    #   api :deny, only: [:impersonate]             # named actions (member, collection, page, standard, batch)
    #   api :deny, except: [:index, :show]
    #   api :deny, attributes: [:superadmin]        # writes that include them, at any depth
    #   api :read_only                              # GET and HEAD only
    #   api :session_only, only: [:destroy]         # not for API tokens
    #   api :superadmin_session, reason: "..."      # registered with ReactiveAdmin.api_guard
    #
    # `:new` and `:create`, and `:edit` and `:update`, go together. `reason:` is what users read
    # instead of the default message. Guards stack and any refusal wins.
    def api(guard = nil, **) = ApiGuards.declare(config, guard, **)
  end

  module ResourceOptions
    def reactive_options = @reactive_options ||= {}
  end

  class ReactiveDSL
    def initialize(config)
      @config = config
      @options = config.reactive_options
    end

    # Columns typeahead searches when this resource is the target of an association input.
    def search(*columns) = @options[:search] = columns

    # Attributes whose values are masked in this resource's index, show and form (see Masking).
    def mask(*attributes) = (@options[:mask] ||= []).concat(attributes.map(&:to_sym))

    # For a resource whose `new` only builds under its parent (an optional `belongs_to`, and a build that
    # needs the parent's id): the manifest stops offering `new` and `create` at the top level.
    def new_needs_parent = @options[:new_needs_parent] = true

    # How a has_many section's rows are laid out: `nested_layout :admin_policy_permissions, :cards`. Left
    # alone, rows with a single control show as a compact list and the rest as cards.
    def nested_layout(association, mode)
      mode = mode.to_s
      raise ArgumentError, "nested_layout #{mode.inspect}: expected one of #{FormHasMany::LAYOUTS.join(", ")}" unless FormHasMany::LAYOUTS.include?(mode)

      (@options[:nested_layout] ||= {})[association.to_sym] = mode
    end

    # Marks this resource's display names as sensitive: lookups returning its records are audited (see
    # LookupAudit). `sensitive false` overrides `config.sensitive_resources`.
    def sensitive(flag = true) = @options[:sensitive] = flag

    # Place this resource in the menu without touching its AA `menu` call: `path` is the group
    # labels from the top (at most 2), an empty path meaning top level. Overridden by ReactiveAdmin.menu.
    def menu(path: nil, priority: nil, label: nil, description: nil, icon: nil)
      MenuOverlay.check_depth!(path.size + 1, "reactive menu path #{path.inspect}") if path
      @options[:menu] = {path: (Array(path).map(&:to_s) if path), priority:, label:, description:, icon:}.compact
    end

    # Lists a member (or GET collection) action as a header button; an action that no action item
    # or content link references is otherwise not listed. `if:` receives the record (nothing for
    # collection actions) and runs in the view context.
    #
    # `expose true` / `expose false` instead serves or denies the whole resource (or page) under
    # `config.expose = :listed`; see Exposure.
    def expose(name, **options)
      return @options[:expose] = name if [true, false].include?(name)

      (@options[:exposed] ||= {})[name.to_sym] = options.fetch(:if, true)
    end

    # Actions whose `q` param is their own search form rather than AA's ransack filter, so the
    # filter guard leaves them alone: `own_query_params :search_toc`. They must not hand `q` to AA's `collection`.
    def own_query_params(*actions) = (@options[:own_query_params] ||= []).concat(actions.map(&:to_sym))

    # The same as `api` outside the block.
    def api(guard = nil, **) = ApiGuards.declare(@config, guard, **)

    # Forces how a custom view is shown (see Ladder): `render_as :frame, action: :care_team_history`.
    # Without `action:` it applies to every custom action of the resource, or to a page's content.
    def render_as(mode, action: nil, custom_key: nil)
      mode = mode.to_s
      raise ArgumentError, "render_as #{mode.inspect}: expected one of #{Ladder::MODES.join(", ")}" unless Ladder::MODES.include?(mode)
      raise ArgumentError, "render_as :custom needs custom_key:" if mode == "custom" && custom_key.blank?

      Ladder.reset!
      (@options[:render_as] ||= {})[(action || "*").to_s] = {mode:, custom_key:}.compact
    end
  end
end
