module ReactiveAdmin
  # `api` in an ActiveAdmin registration: what the API refuses to serve or write, however the caller
  # authenticates. The classic admin is unaffected. Enforced on the actual controller and action of
  # every API request, so it holds for the React client and for anything else that dispatches through
  # the API, never on what the manifest advertises.
  #
  # A guard is `:deny`, `:read_only`, `:session_only` or a name registered with `ReactiveAdmin.api_guard`.
  # The built-ins are static: the metadata of a channel (a session, or a token) already leaves out or
  # marks what they refuse. A registered guard runs per request, so the metadata only says it may refuse.
  module ApiGuards
    STATIC = %i[deny read_only session_only].freeze
    ACTION_MESSAGE = "This isn't available through the API. Use the classic admin.".freeze
    MESSAGES = {
      deny: ACTION_MESSAGE,
      read_only: "The API only reads this. Use the classic admin to change it.".freeze,
      session_only: "This isn't available to API tokens. Use the classic admin.".freeze
    }.freeze
    API_SUFFIX = /\.(reactiveadmin|csv)\z/
    # A form you can't open is one you may not submit, and the other way round.
    PAIRS = {"new" => "create", "create" => "new", "edit" => "update", "update" => "edit"}.freeze
    # The gem's own endpoints serve the data of the action they stand in for.
    ENDPOINTS = {"reactiveadmin_meta" => "index", "reactiveadmin_page" => "index", "reactiveadmin_labels" => "show", "reactiveadmin_value" => "show"}.freeze
    STANDARD = %w[index show new create edit update destroy batch_action].freeze
    UNSAFE = %w[create update destroy batch_action].freeze

    Declaration = Data.define(:guard, :only, :except, :attributes, :reason) do
      def name = guard.to_s

      def static? = STATIC.include?(guard)

      def blanket? = only.nil? && except.nil? && attributes.nil?
    end
    Refusal = Data.define(:guard, :message, :attributes)

    # The channel of the request being served: :session for the React client, :token for bearer
    # requests (the MCP endpoint, scripts). Unset means :token, so metadata never offers more than it should.
    class Current < ActiveSupport::CurrentAttributes
      attribute :channel
    end

    # Prepended to the resource and page controllers. After authentication, so a signed-out client
    # learns nothing, and next to Exposure, before any authorization or host callback that acts.
    module Guard
      private

      def authenticate_active_admin_user
        super
        reject_api_denied unless performed?
      end

      def reject_api_denied
        return if @reactiveadmin_api_clear || !ApiGuards.api_scope?(self)

        refusal = ApiGuards.check(self)
        return @reactiveadmin_api_clear = true unless refusal

        render_api_denied(refusal)
      end

      def render_api_denied(refusal)
        render_api_error(:api_denied, refusal.message, 403, guard: refusal.guard, classic_url: ApiGuards.classic_url(self), attributes: refusal.attributes)
      end
    end

    # Outermost, so it also covers a controller that skips authentication, and runs before the page
    # controller renders its content to shape a write.
    module Backstop
      private

      def send_action(*)
        reject_api_denied
        super unless performed?
      end
    end

    module_function

    def channel = Current.channel || :token

    def channel_of(request) = Auth.token_based?(request) ? :token : :session

    def with_channel(channel)
      previous = Current.channel
      Current.channel = channel
      yield
    ensure
      Current.channel = previous
    end

    def registry = ReactiveAdmin.config.api_guards

    def registered(name) = registry.find { |key, _| key.to_s == name.to_s }&.last

    def declare(config, guard, only: nil, except: nil, attributes: nil, reason: nil)
      raise ArgumentError, "api needs a guard: false, :deny, :read_only, :session_only or a registered name" if guard.nil?
      raise ArgumentError, "api: only: and except: don't combine" if only && except

      guard = (guard == false) ? :deny : guard.to_sym
      unknown_guard!(guard) unless STATIC.include?(guard) || registered(guard)
      raise ArgumentError, "api :read_only has no attributes: it refuses every write already" if guard == :read_only && attributes

      declaration = Declaration.new(guard:, only: normalize(only), except: normalize(except), attributes: normalize(attributes), reason: reason.presence)
      ((config.reactive_options[:api_guards] ||= []) << declaration).last
    end

    def unknown_guard!(guard)
      raise ArgumentError, "api #{guard.inspect}: no guard by that name. Built in: #{STATIC.map(&:inspect).join(", ")}; " \
        "register your own with ReactiveAdmin.api_guard(#{guard.inspect}) { |user, request| ... } before the admin files load"
    end

    def normalize(list) = (Array(list).flatten.map(&:to_s) unless list.nil?)

    def declarations(config) = config.try(:reactive_options)&.dig(:api_guards) || []

    def declared?(config) = declarations(config).any?

    def actions_of(config) = declarations(config).select { it.attributes.nil? }

    def attributes_of(config) = declarations(config).select(&:attributes)

    def expand(names) = names.flat_map { [it.to_s, PAIRS[it.to_s]] }.compact.uniq

    def matches?(list, names) = expand(names).intersect?(list)

    def applies?(declaration, names)
      return matches?(declaration.only, names) if declaration.only
      return !matches?(declaration.except, names) if declaration.except

      true
    end

    # Whether a static guard refuses this request or action in `channel`. A read-only guard also
    # closes the form of a write it refuses.
    def refuses_statically?(declaration, config, names, verb:, channel:)
      case declaration.guard
      when :deny then true
      when :session_only then channel == :token
      when :read_only then unsafe?(config, names, verb)
      else false
      end
    end

    def unsafe?(config, names, verb)
      return true if verb && %w[GET HEAD].exclude?(verb.to_s.upcase)

      expand(names).any? { UNSAFE.include?(it) || custom_unsafe?(config, it) }
    end

    def custom_unsafe?(config, name)
      declaration = AA.custom_actions(config).find { it.name.to_s == name }
      !!declaration && Array.wrap(declaration.http_verb).any? { it.to_s.upcase != "GET" }
    end

    # The declaration that statically refuses these actions in `channel`, for the metadata.
    def denial(config, names, verb: nil, channel: self.channel)
      actions_of(config).find do |declaration|
        declaration.static? && applies?(declaration, names) && refuses_statically?(declaration, config, names, verb:, channel:)
      end
    end

    def denies?(config, *names, verb: nil) = !denial(config, names.flatten.map(&:to_s), verb:).nil?

    # Whether a session-only guard covers these actions, which a session still gets to use.
    def session_only?(config, names)
      channel == :session && actions_of(config).any? { it.guard == :session_only && applies?(it, names) }
    end

    # The registered guard that may refuse these actions, annotated since it can't be known ahead.
    def custom_for(config, names) = actions_of(config).find { !it.static? && applies?(it, names) }

    def message(declaration) = declaration.reason || MESSAGES.fetch(declaration.guard, ACTION_MESSAGE)

    # A resource or page nothing of which the channel may use.
    def whole?(config, channel: self.channel)
      actions_of(config).any? { it.blanket? && refuses_statically?(it, config, [], verb: nil, channel:) }
    end

    # Nothing of it is reachable through the API: denied whole, or every action it serves denied one by one.
    def fully_denied?(config, channel: :session)
      return true if whole?(config, channel:)

      names = served_actions(config)
      declared?(config) && names.any? && names.all? { denial(config, [it], channel:) }
    end

    def served_actions(config)
      return known_actions(config) if AA.page?(config)

      [*Registry.actions(config).map(&:to_s), *known_actions(config) - STANDARD]
    end

    # The action a request exercises: refused when a guard refuses it, evaluated for real (registered
    # guards run). `verb` is the request's own.
    def refusal(controller, config, names, verb: controller.request.request_method)
      channel = channel_of(controller.request)
      actions_of(config).each do |declaration|
        next unless applies?(declaration, names)
        next unless refused?(declaration, controller, config, names, verb:, channel:)

        return Refusal.new(declaration.name, message(declaration), nil)
      end
      nil
    end

    def refused?(declaration, controller, config, names, verb:, channel:)
      return refuses_statically?(declaration, config, names, verb:, channel:) if declaration.static?

      !permits?(declaration, controller)
    end

    # A registered guard that is missing or raises refuses: nothing here fails open.
    def permits?(declaration, controller)
      guard = registered(declaration.guard) or return false
      !!guard.call(ReactiveAdmin.current_user(controller), controller.request)
    rescue => e
      Rails.logger.warn("[reactiveadmin] api guard #{declaration.name} raised #{e.class}; refused")
      false
    end

    # An API request by its format, or by living under the mount whatever format it claims.
    def api_scope?(controller)
      mount = ReactiveAdmin.config.mount_path.to_s.chomp("/")
      controller.send(:reactiveadmin_request?) || (mount.present? && controller.request.path.start_with?("#{mount}/"))
    end

    # The action names this request exercises: its own, the one a gem endpoint stands in for, or the
    # batch action it names.
    def names_for(controller)
      action = controller.action_name
      params = controller.params
      case action
      when "batch_action" then [action, (params[:batch_action] if params[:batch_action].is_a?(String))].compact
      when "reactiveadmin_options", "reactiveadmin_lookup" then [form_action(params)]
      else [ENDPOINTS.fetch(action, action)]
      end
    end

    def form_action(params)
      return "index" unless params[:context] == "form"

      params[:id].present? ? "edit" : "new"
    end

    def check(controller)
      config = AA.config_of(controller)
      return unless declared?(config)

      refusal(controller, config, names_for(controller)) || attribute_refusal(controller, config)
    end

    # Guarded attributes the request writes, at any depth: key names are compared, wherever the schema
    # maps them. Only unsafe verbs write; reads of these attributes are unchanged.
    def attribute_refusal(controller, config)
      request = controller.request
      return if request.get? || request.head?

      names = names_for(controller)
      keys = keys_in(request.parameters)
      channel = channel_of(request)
      refused = attributes_of(config).filter_map do |declaration|
        next unless applies?(declaration, names)

        written = watched(config, declaration).filter_map { |key, declared| declared if keys.include?(key) }.uniq
        [declaration, written] if written.any? && refused?(declaration, controller, config, names, verb: request.request_method, channel:)
      end
      return if refused.empty?

      attributes = refused.flat_map(&:last).uniq.sort
      declaration = refused.first.first
      Refusal.new(declaration.name, declaration.reason || attribute_message(declaration, attributes), attributes)
    end

    def attribute_message(declaration, attributes)
      who = (declaration.guard == :session_only) ? "A signed-in admin session" : "Only the classic admin"
      "#{who} can change: #{attributes.join(", ")}"
    end

    # An association's foreign key and ids are the attribute by another name.
    def watched(config, declaration)
      declaration.attributes.each_with_object({}) do |name, map|
        [name, "#{name}_attributes", *association_keys(config, name)].each { map[it] = name }
      end
    end

    def association_keys(config, name)
      association = config.try(:resource_class)&.reflect_on_association(name)
      return [] unless association

      association.collection? ? ["#{name.to_s.singularize}_ids"] : Array(association.foreign_key).map(&:to_s)
    end

    def keys_in(value, keys = Set.new)
      case value
      when Hash
        value.each do |key, nested|
          keys << key.to_s
          keys_in((key.to_s == "batch_action_inputs") ? parsed(nested) : nested, keys)
        end
      when Array then value.each { keys_in(it, keys) }
      end
      keys
    end

    def parsed(value)
      value.is_a?(String) ? JSON.parse(value) : value
    rescue JSON::ParserError
      nil
    end

    # Attribute declarations of the named actions that a static guard refuses in `channel`.
    def denied_attributes(config, names, channel: self.channel)
      attributes_of(config).select do |declaration|
        declaration.static? && applies?(declaration, names) && refuses_statically?(declaration, config, names, verb: nil, channel:)
      end
    end

    # The keys a write of these actions may not carry in `channel`, for the write schema and form fields.
    def reserved_keys(config, names, channel: self.channel)
      denied_attributes(config, names, channel:).flat_map { watched(config, it).keys }
    end

    # The registered guard that may refuse a write of one of these keys.
    def attribute_guard(config, names, keys)
      attributes_of(config).find { !it.static? && applies?(it, names) && watched(config, it).keys.intersect?(keys) }
    end

    # The classic page of the request: the same page when it can be fetched, else the record's or
    # the resource's.
    def classic_url(controller)
      config = AA.config_of(controller)
      request = controller.request
      action = controller.action_name
      return same_page(request) if request.get? && (action == "reactiveadmin_page" || !action.start_with?("reactiveadmin_"))

      AA.page?(config) ? page_url(config, controller.params) : record_url(config, controller.params)
    end

    def same_page(request)
      path = request.path.delete_prefix(ReactiveAdmin.config.mount_path).sub(API_SUFFIX, "").sub("/_pages/", "/")
      [path, request.query_string.presence].compact.join("?")
    end

    def record_url(config, params)
      collection = Paths.collection(config, parent_id: Paths.parent_id(config, params))
      return collection if params[:id].blank? || !Registry.actions(config).include?(:show)

      File.join(collection, ERB::Util.url_encode(params[:id].to_s))
    end

    def page_url(config, params)
      parent = config.belongs_to_config if Paths.nested?(config)
      ["", ReactiveAdmin.config.namespace, *(parent && [Registry.route_key(parent.target), params[parent.to_param]]), config.underscored_resource_name].compact.join("/")
    end

    # An action of a payload turned into a link to the classic admin when a static guard refuses it
    # (nothing in it can run through the API), or annotated when a registered guard may.
    def mark(action, config, *names)
      names = names.map(&:to_s)
      declaration = denial(config, names, verb: action[:method])
      return annotate(action, custom_for(config, names)) unless declaration

      action.except(:api_path, :form_path, :view, :confirm).merge(
        api_denied: true, classic_url: action_url(action), supported: false, disabled_reason: message(declaration)
      )
    end

    def annotate(payload, declaration) = declaration ? payload.merge(api_guard: declaration.name) : payload

    # A GET is its own classic page; anything else lands on the page its target belongs to.
    def action_url(action)
      href = action[:href].to_s
      return href if action[:method].to_s == "get"

      path = href.split("?").first.to_s
      %w[member collection custom].include?(action[:kind].to_s) ? File.dirname(path) : path
    end

    # What the manifest says of a resource that is only partly denied, in the current channel.
    def summary(config)
      return unless declared?(config) && !whole?(config)

      known = known_actions(config).to_h { [it, action_names(config, it)] }
      denied = known.select { |_, names| denies?(config, *names) }.keys
      guarded = (known.keys - denied).to_h { [it, custom_for(config, known[it])&.name] }.compact
      attributes = known.values.flat_map { denied_attributes(config, it) }.uniq.flat_map(&:attributes).uniq
      summary = {actions: denied.presence, attributes: attributes.presence, guards: guarded.presence}.compact
      summary.merge(classic_url: (Paths.collection(config) unless Paths.nested?(config))).compact unless summary.empty?
    end

    # A batch action is named with the batch endpoint; the rest by themselves.
    def action_names(config, name)
      standalone = AA.page?(config) || STANDARD.include?(name) || AA.custom_actions(config).any? { it.name.to_s == name }
      standalone ? [name] : ["batch_action", name]
    end

    # Accepted decisions, for the doctor.
    def accepted
      [*Registry.resources, *Registry.pages].flat_map do |config|
        declarations(config).map do |declaration|
          {key: Exposure.key(config), kind: AA.page?(config) ? "page" : "resource", guard: declaration.name, whole: declaration.blanket?,
           only: declaration.only, except: declaration.except, attributes: declaration.attributes, reason: declaration.reason}.compact
        end
      end
    end

    # A name that matches no action guards nothing, which a typo must not do quietly.
    def audit
      [*Registry.resources, *Registry.pages].flat_map do |config|
        declarations(config).flat_map do |declaration|
          (Array(declaration.only) + Array(declaration.except) - known_actions(config)).map do |name|
            {kind: :api_guard_unknown_action, resource: Exposure.key(config), action: name,
             reason: "api #{declaration.guard.inspect} names #{name}, which matches no action of this #{AA.page?(config) ? "page" : "resource"}"}
          end
        end
      end
    end

    def known_actions(config)
      return ["index", *AA.custom_actions(config).map { it.name.to_s }] if AA.page?(config)

      [*STANDARD, *AA.custom_actions(config).map { it.name.to_s }, *AA.batch_actions(config).map { it.sym.to_s }]
    end
  end
end
