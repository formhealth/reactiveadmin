module ReactiveAdmin
  # Turns the links and button_to forms AA renders (action items, row items, content) into
  # contract Actions, mapping classic URLs back to the API where the route is one of ours.
  class ActionLinks
    VERBS = %w[get post put patch delete].freeze
    PERMISSIONS = {"edit" => AA::Auth::EDIT, "destroy" => AA::Auth::DESTROY}.freeze
    UNSUPPORTED = "Not available here; open it in the classic admin".freeze
    CLASSIC_ONLY = "Available in the classic admin".freeze
    # What the browser's own POST would carry; the client supplies the session's CSRF token instead.
    FRAMEWORK_FIELDS = %w[authenticity_token _method utf8].freeze
    # Unusable path shapes: dot segments and encoded slashes, which a browser would resolve to somewhere else.
    UNSAFE_PATH = %r{/\.\.?(/|\z)|%2[ef]|\\}i

    # Elements that act rather than navigate: rails-ujs links and single-button forms.
    def self.control?(el)
      case el.name
      when "a" then el["data-confirm"].present? || verb(el["data-method"]) != "get"
      when "form" then single_button?(el)
      end
    end

    # Every control in rendered html. Dropdown toggles are `a href="#"`; their entries count instead.
    def self.controls(html)
      fragment = HtmlPolicy.parse(html) or return []

      fragment.css("a, form").reject do |el|
        el.ancestors("form").any? || el.classes.include?("dropdown_menu_button")
      end
    end

    def self.verb(value) = value.to_s.downcase.presence_in(VERBS) || "get"

    def self.single_button?(form)
      inputs = form.css("input, button, select, textarea")
      buttons, others = inputs.partition { it["type"] == "submit" || (it.name == "button" && it["type"].blank?) }
      buttons.one? && others.all? { it["type"] == "hidden" }
    end

    # `base_url` makes the links to this host's own non-admin paths absolute: the SPA may be served from
    # another origin than the API.
    def initialize(host: nil, base_url: nil, authorizer: nil, subject: nil)
      @host = host
      @base_url = base_url
      @authorizer = authorizer
      @subject = subject
    end

    def action(el, placement:, key: nil)
      label, href, verb, confirm = parse(el)
      base = {label:, placement:, method: verb, confirm:}
      uri = parse_uri(href)
      return unsupported(base, key, href) if uri.nil? || (uri.path.blank? && uri.host.blank?)
      return navigation(base, key, uri, el) if verb == "post" && navigable?(uri)
      return external(base, key, uri) if foreign?(uri) || (verb == "get" && outside_admin?(uri))

      route = recognize(uri.path, verb)
      config = Registry.for_controller_path(route[:controller]) if route
      target = [uri.path, uri.query].compact.join("?")
      return page(base, key, route, target) if route && !config
      return unsupported(base, key, href) unless config
      return classic_only(base, key, href) unless Exposure.allowed?(config)

      # Route params come back as binary strings, which parameterize refuses.
      name = route[:action].dup.force_encoding(Encoding::UTF_8)
      ApiGuards.mark(internal(base, config, name, key, target), config, name)
    end

    # Links the SPA can't route: other hosts, mailto and tel, and this host's paths outside the admin namespace.
    def external?(uri) = foreign?(uri) || outside_admin?(uri)

    def absolute(uri) = (@base_url && uri.relative?) ? URI.join(@base_url, uri.to_s).to_s : uri.to_s

    private

    # A POST the browser itself must make, to a route of this host outside the admin and the API mount (an OmniAuth
    # start): never through the API, so never for a token. Only this origin, over http(s), at a plain path.
    def navigable?(uri)
      web = uri.scheme.nil? || %w[http https].include?(uri.scheme.downcase)
      path = uri.path.to_s
      web && !foreign?(uri) && uri.userinfo.nil? && same_origin?(uri) && path.start_with?("/") && !path.match?(UNSAFE_PATH) && outside_admin?(uri) && !under_mount?(path)
    end

    def same_origin?(uri)
      return uri.scheme.nil? if uri.host.nil?

      origin = (URI.parse(@base_url) if @base_url)
      origin.nil? ? uri.host.casecmp?(@host.to_s) : [uri.scheme.downcase, uri.host.downcase, uri.port] == [origin.scheme, origin.host.downcase, origin.port]
    end

    def under_mount?(path)
      mount = ReactiveAdmin.config.mount_path.to_s.chomp("/")
      mount.present? && (path == mount || path.start_with?("#{mount}/"))
    end

    # Nothing here for a token: it can't hold the cookie the target route expects, and it has no browser to navigate.
    def navigation(base, key, uri, el)
      return unless ApiGuards.channel == :session

      fields = el.css("input[type=hidden]").reject { FRAMEWORK_FIELDS.include?(it["name"]) || it["name"].blank? }.to_h { [it["name"], it["value"].to_s] }
      {key: slug(key || base[:label]), kind: "link", href: absolute(uri), navigate: true, params: fields.presence, enabled: true, **base}.compact
    end

    def foreign?(uri) = uri.scheme.in?(%w[mailto tel]) || (uri.host.present? && !uri.host.casecmp?(@host.to_s))

    def outside_admin?(uri) = uri.path.to_s.start_with?("/") && !Paths.admin?(uri.path)

    def parse(el)
      if el.name == "form"
        button = el.at_css("button, input[type=submit]")
        override = el.at_css("input[name=_method]")&.[]("value")
        [(button.text.presence || button["value"]).to_s.strip, el["action"], self.class.verb(override || el["method"]),
          (button["data-confirm"] || el["data-confirm"]).presence]
      else
        [el.text.strip, el["href"], self.class.verb(el["data-method"]), el["data-confirm"].presence]
      end
    end

    def parse_uri(href)
      URI.parse(href.to_s)
    rescue URI::InvalidURIError
      nil
    end

    def recognize(path, verb)
      Rails.application.routes.recognize_path(path, method: verb.upcase)
    rescue ActionController::RoutingError
      nil
    end

    def internal(base, config, route_action, key, href)
      kind = kind(config, route_action)
      member_or_collection = %w[member collection].include?(kind)
      key = route_action if member_or_collection || PERMISSIONS.key?(route_action)
      permission = member_or_collection ? route_action.to_sym : PERMISSIONS[route_action]
      enabled = permission.nil? || permitted?(config, permission)
      reason = "You don't have permission to #{base[:label].downcase}" unless enabled
      view = Ladder.view(config, route_action, href:) if member_or_collection && base[:method] == "get"
      {key: slug(key || base[:label]), kind:, href:, api_path: Paths.api(href), enabled:, disabled_reason: reason, view:, **base}.compact
    end

    # A link to a register_page or to one of its GET actions: shown by the ladder, or not at all.
    # A declared page action with another verb is run through the API.
    def page(base, key, route, href)
      page = Registry.page_for_controller_path(route[:controller])
      return classic_only(base, key, href) if page && !Exposure.allowed?(page)

      name = route[:action].dup.force_encoding(Encoding::UTF_8)
      if page && ApiGuards.denies?(page, name, verb: base[:method])
        return ApiGuards.mark({key: slug(key || name), kind: "custom", href:, enabled: true, **base}, page, name)
      end
      return page_action(base, key, page, name, href) if page && base[:method] != "get"

      view = (name == "index") ? Ladder.page_view(page, href:) : Ladder.view(page, name, href:) if page
      return unsupported(base, key, href) unless view

      {key: slug(key || base[:label]), kind: "link", href:, api_path: Paths.api(href), enabled: true, view:, **base}.compact
    end

    def page_action(base, key, page, name, href)
      declared = page.page_actions.any? { it.name.to_s == name && Array.wrap(it.http_verb).include?(base[:method].to_sym) }
      return unsupported(base, key, href) unless declared

      {key: slug(key || name), kind: "custom", href:, api_path: Paths.api(href), enabled: true, **base}.compact
    end

    def external(base, key, uri)
      {key: slug(key || base[:label]), kind: "link", href: absolute(uri), external: true, enabled: true, **base}.compact
    end

    def unsupported(base, key, href, reason = UNSUPPORTED)
      {key: slug(key || base[:label]), kind: "link", href: href.presence, supported: false, enabled: false,
       disabled_reason: reason, **base}.compact
    end

    def classic_only(base, key, href) = unsupported(base, key, href, CLASSIC_ONLY)

    def kind(config, route_action)
      name = route_action.to_sym
      if config.member_actions.any? { it.name == name } then "member"
      elsif config.collection_actions.any? { it.name == name } then "collection"
      else
        PERMISSIONS.key?(route_action) ? route_action : "link"
      end
    end

    def slug(value) = value.to_s.parameterize(separator: "_")

    # A member action is checked against the record it targets, which is the subject only when
    # the link points at the same resource.
    def permitted?(config, permission)
      subject = @subject.is_a?(config.resource_class) ? @subject : config.resource_class
      @authorizer.nil? || @authorizer.authorized?(permission, subject, config:)
    rescue
      false
    end
  end
end
