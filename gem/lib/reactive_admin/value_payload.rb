module ReactiveAdmin
  # JSON values are often large and sensitive, so payloads carry a summary and an `expand_path` to
  # the audited `_value` endpoint. Only a small value without masked keys is ever sent inline: on
  # show, and in an edit form, where the same rule applies to the control.
  module ValuePayload
    MASK = "[masked]".freeze
    MAX_KEYS = 20
    MAX_PATH_DEPTH = 32
    NotFound = ActiveRecord::RecordNotFound
    Forbidden = Class.new(StandardError)

    # Where a value lives: enough to point `expand_path` at it. `via` is the page it renders on
    # (index, show, form); the token carries it so `_value` knows which permission to check.
    Source = Struct.new(:config, :record, :field, :inline, :controller, :via)

    module_function

    def node(value, source)
      return {type: "empty"} if value.blank?

      return {type: "json", value:} if source&.inline && inline?(value, source.config)

      {type: "json", summary: summary(value), expand_path: expand_path(source)}.compact
    end

    def inline?(value, config) = value.to_json.bytesize <= ReactiveAdmin.config.inline_json_limit && !masked_key?(value, config)

    def summary(value) = {kind: value.is_a?(Hash) ? "object" : "array", keys: keys(value), size: value.to_json.bytesize}

    def expand_path(source)
      return unless source&.record && source.field

      query = {field: source.field}
      query[:token] = ValueToken.mint(source.controller, source.config, source.record, source.field, source.via) if ReactiveAdmin.config.value_token
      "#{Paths.api(File.join(Paths.member(source.config, source.record), "_value"))}?#{query.to_query}"
    end

    # Top-level key names only, to say what is inside without saying what it holds.
    def keys(value) = value.is_a?(Hash) ? value.keys.first(MAX_KEYS).map(&:to_s) : []

    def masked_key?(value, config)
      case value
      when Hash then value.any? { |key, nested| Masking.attribute?(key, config) || masked_key?(nested, config) }
      when Array then value.any? { masked_key?(it, config) }
      else false
      end
    end

    def mask(value, config)
      case value
      when Hash then value.to_h { |key, nested| [key, (Masking.attribute?(key, config) && nested.present?) ? MASK : mask(nested, config)] }
      when Array then value.map { mask(it, config) }
      else value
      end
    end

    def json?(value) = (value.is_a?(Hash) || value.is_a?(Array)) && Values.plain?(value)

    # The `_value` answer for `field` of a record the caller may already read. The `expand_path` token
    # says a page rendered the field for this user; without one (`config.value_token = false`) the pages
    # are rendered again to find out. Either way an attribute no page shows is a 404, so the endpoint can
    # never read more than the pages already show.
    def fetch(controller, record, field, path = nil, token: nil)
      config = AA.config_of(controller)
      raise NotFound unless permitted?(controller, config, record, field, token)

      value = AA.find_value(controller.view_context, record, field.to_sym)
      return text(value, config, field, path) if value.is_a?(String)
      raise NotFound unless json?(value)

      dig(mask(value.as_json, config), path)
    end

    # Only a plain text column is served as a string: the full text a default view truncated.
    def text(value, config, field, path)
      raise NotFound unless path.blank? && ImplicitDefaults.text_column?(config, field)

      value
    end

    def permitted?(controller, config, record, field, token)
      return rendered?(controller, config, record, field) unless ReactiveAdmin.config.value_token

      page = ValueToken.verify(controller, config, record, field, token) or raise Forbidden
      return false if field.empty? || Masking.attribute?(field, config)

      (page == "form") ? editable?(controller, config, record) : Registry.actions(config).include?(page.to_sym)
    end

    def editable?(controller, config, record) = Registry.actions(config).include?(:edit) && Authorizer.for(controller).authorized?(AA::Auth::UPDATE, record)

    def rendered?(controller, config, record, field)
      return false if field.empty? || Masking.attribute?(field, config)

      actions = Registry.actions(config)
      named = ->(attributes) { attributes.any? { it.to_s == field } }
      (actions.include?(:index) && named.call(IndexPayload.new(controller).symbol_columns)) ||
        (actions.include?(:show) && named.call(ShowPayload.new(controller).rendered_attributes(record))) ||
        form_field?(controller, config, record, field)
    end

    # A json control of the edit form, for whoever may update the record: the form summarizes it and
    # this is how its editor loads the value.
    def form_field?(controller, config, record, field)
      return false unless editable?(controller, config, record)

      sections = FormPayload.new(controller, only: field).schema.sections
      sections.any? { |section| section[:fields]&.any? { it[:name] == field && it[:control] == "json" && !it[:masked] } }
    end

    def dig(value, path)
      keys = path.to_s.split(".", -1)
      raise NotFound if keys.size > MAX_PATH_DEPTH

      keys.reduce(value) do |node, key|
        case node
        when Hash then node.fetch(key) { raise NotFound }
        when Array then key.match?(/\A\d+\z/) ? node.fetch(key.to_i) { raise NotFound } : raise(NotFound)
        else raise NotFound
        end
      end
    end

    # Extended onto the show view: json attribute rows become typed nodes, and the attributes
    # rendered for the record are noted for the `_value` allowlist.
    module Display
      def reactiveadmin_attributes = (@reactiveadmin_attributes ||= Set.new)

      def format_attribute(resource, attr)
        config = @reactiveadmin_value_config
        return super unless attr.is_a?(Symbol) || attr.is_a?(String)
        return super unless resource.instance_of?(config.resource_class)

        reactiveadmin_attributes << attr.to_s
        value = AA.find_value(self, resource, attr)
        return super unless ValuePayload.json?(value) && !Masking.attribute?(attr, config)

        NodeRegistry.marker(ValuePayload.node(value, Source.new(config:, record: resource, field: attr.to_s, inline: true, controller:, via: "show")))
      end
    end

    def install(view, config)
      view.instance_variable_set(:@reactiveadmin_value_config, config)
      view.extend(Display)
    end
  end
end
