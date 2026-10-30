module ReactiveAdmin
  module OpenApi
    # Assembles the document: the resources and pages the user may open, the metadata endpoints, and
    # only those of core's component schemas the paths reach. Keys and operations come out in a fixed
    # order, so two builds of the same code and permissions are equal and a diff shows real changes.
    class Builder
      include Parts

      META_TAG = "meta".freeze
      DEFAULT_INFO = {title: "Admin API"}.freeze
      REF = %r{\A#/components/(?<kind>\w+)/(?<name>.+)\z}

      def initialize(user, controller:, full:, channel: nil)
        @ctx = Context.new(user, controller:, full:)
        @channel = channel || :session
      end

      def call = ApiGuards.with_channel(@channel) { document }

      private

      def document
        resources = documents(@ctx.resources.sort_by { it[:key] }) { ResourceDoc.new(@ctx, it) }
        pages = documents(readable_pages.sort_by { Menu.page_key(it) }) { PageDoc.new(@ctx, it) }
        tags = [*resources.pluck(:tag), *pages.pluck(:tag), meta_tag]
        paths = ordered([meta_paths, *resources.pluck(:paths), *pages.pluck(:paths)].reduce({}, :merge)).deep_stringify_keys
        {
          openapi: SPEC_VERSION,
          info:, servers: [{url: "/"}],
          tags: arrange(tags, resources, pages), "x-tagGroups": groups(resources, pages), security: Security.requirement(write: false)
        }.deep_stringify_keys.merge("paths" => paths, "components" => components(paths, resources))
      end

      def info = DEFAULT_INFO.merge(version: VERSION).merge(ReactiveAdmin.config.openapi.info.to_h.deep_symbolize_keys)

      # A resource or page whose document can't be built is left out and reported, not a failed document.
      def documents(items)
        items.filter_map do |item|
          yield(item).call
        rescue => e
          Degradation.record(kind: :openapi_document_dropped, where: "openapi/#{item.try(:name) || item[:key]}", reason: "Document raised #{e.class}; left out")
          nil
        end
      end

      def readable_pages
        Registry.pages.select { Exposure.allowed?(it) && !ApiGuards.denies?(it, "index") && @ctx.authorized?(AA::Auth::READ, it, it) }
      end

      def ordered(paths) = paths.transform_values { |item| item.sort_by { |verb, _| VERBS.index(verb.to_s) }.to_h }

      # Metadata

      def meta_tag
        {name: META_TAG, "x-displayName": "Session and metadata", description: "The manifest, the session and CSRF token, and this document."}
      end

      def meta_paths
        ns = "/#{ReactiveAdmin.config.namespace}"
        {
          Paths.api("#{ns}/_manifest") => {get: meta_operation("getManifest", "Manifest of served resources and the menu", success("The manifest", schema_ref("Manifest")), [403])},
          Paths.api("#{ns}/_session") => {get: meta_operation("getSession", "Current user and CSRF token", success("The session", schema_ref("Session")), [])},
          Paths.api("#{ns}/_openapi") => {get: meta_operation("getOpenApi", "This OpenAPI document", openapi_response, [403])}
        }.merge(mcp_paths(ns))
      end

      # Only where a token can call it: a bearer adapter is configured and MCP is on for this user.
      def mcp_paths(ns)
        mcp = ReactiveAdmin.config.mcp
        return {} unless Auth.bearer? && (@ctx.full? ? mcp.possibly_enabled? : mcp.enabled_for?(@ctx.user))

        operation = Core.operation("/admin/_mcp", "post").merge("tags" => [META_TAG], "security" => Security.token_requirement)
        operation["operationId"] = @ctx.ids.claim(operation["operationId"])
        {Paths.api("#{ns}/_mcp") => {post: operation}}
      end

      def meta_operation(id, summary, response, errors)
        operation(id: @ctx.ids.claim(id), summary:, tags: [META_TAG], responses: {200 => response}, errors:)
      end

      def openapi_response
        success("An OpenAPI 3.1 document of what the user may do, as plain JSON", {type: "object", additionalProperties: true})
      end

      # Tags in the order of their groups, so a viewer's sidebar follows the admin's own menu.

      def arrange(tags, resources, pages)
        order = group_names(resources, pages).values.flatten
        by_name = tags.index_by { it[:name] }
        [*order.filter_map { by_name[it] }, by_name[META_TAG]]
      end

      def groups(resources, pages)
        group_names(resources, pages).map { |name, tags| {name:, tags:} } + [{name: "Meta", tags: [META_TAG]}]
      end

      def group_names(resources, pages)
        names = resources.map { it.dig(:tag, :name) } + pages.map { it.dig(:tag, :name) }
        placed = menu_groups.transform_values { |tags| tags & names }.reject { |_, tags| tags.empty? }
        rest = names - placed.values.flatten
        rest.empty? ? placed : placed.merge("Other" => rest)
      end

      # Group name (the top-level menu group) to the tags of the resources and pages placed in it.
      def menu_groups
        walk(@ctx.manifest.menu(@ctx.resources).as_json, nil, {})
      rescue => e
        Degradation.record(kind: :openapi_degraded, where: "openapi/menu", reason: "Menu raised #{e.class}; tags are not grouped")
        {}
      end

      def walk(nodes, group, found)
        nodes.each do |node|
          tag = node[:resource] || (PageDoc.tag_name(Registry.find_page(node[:page])) if node[:page])
          (found[group || (node[:page] ? "Pages" : "Resources")] ||= []) << tag if tag
          walk(node[:children], group || (node[:label] if node[:kind] == "group"), found)
        end
        found.transform_values(&:uniq)
      end

      # Components: core's, plus the generated ones, kept only where a path reaches them.

      def components(paths, resources)
        pool = Core::KINDS.to_h { [it, Core.components(it).deep_dup] }
        pool["schemas"] = pool["schemas"].merge(resources.pluck(:schemas).reduce({}, :merge).deep_stringify_keys) { |name, *| raise "reactiveadmin: generated schema #{name} clashes with core's" }
        pool["parameters"] = pool["parameters"].merge(resources.pluck(:parameters).reduce({}, :merge))
        pool["responses"] = pool["responses"].merge(RESPONSES.deep_stringify_keys)
        used = reachable(paths, pool)
        used.transform_values { |entries| entries.sort.to_h }.merge("securitySchemes" => Security.schemes).sort.to_h
      end

      def reachable(paths, pool)
        used = Hash.new { |hash, kind| hash[kind] = {} }
        queue = refs_in(paths)
        until queue.empty?
          match = REF.match(queue.shift) or next
          kind = match[:kind]
          name = match[:name]
          next if used[kind].key?(name) || !pool.dig(kind, name)

          used[kind][name] = pool.dig(kind, name)
          queue.concat(refs_in(used[kind][name]))
        end
        used
      end

      def refs_in(node)
        case node
        when Hash then node.flat_map { |key, value| (key == "$ref") ? [value] : refs_in(value) }
        when Array then node.flat_map { refs_in(it) }
        else []
        end
      end
    end
  end
end
