module ReactiveAdmin
  # Menu placement declared in one place, on top of ActiveAdmin's own menu (which stays the
  # fallback for anything not placed):
  #
  #   ReactiveAdmin.menu do
  #     group "Setup", priority: 90, icon: "settings" do
  #       group "Billing" do
  #         resources :billing_plans, :invoices
  #         page :batch_operations
  #         link "Sidekiq", url: "/sidekiq", if: -> { current_active_admin_user.superadmin? }
  #       end
  #     end
  #     hide :legacy_reports, :batch_operations
  #   end
  #
  # Precedence: overlay > `reactive { menu path: [...] }` on the resource > AA's `menu parent:`.
  # Nodes the user may not see stay out, and groups left empty are dropped. Placing a resource or page
  # that AA hides (`menu false`) puts it in this menu only; AA's own menu is untouched.
  class MenuOverlay
    MAX_DEPTH = 3
    DEFAULT_PRIORITY = 10
    UNSEQUENCED = 1_000_000

    class DepthError < StandardError; end

    Entry = Struct.new(:kind, :key, :label, :id, :priority, :description, :icon, :url, :display_if, :verb, :children)

    class Builder
      attr_reader :entries

      def initialize(depth)
        @depth = depth
        @entries = []
      end

      # Groups hold items one level below, so a group may not sit at the last level.
      def group(label, priority: nil, description: nil, icon: nil, id: nil, &block)
        MenuOverlay.check_depth!(@depth + 1, "group #{label.inspect}")
        child = Builder.new(@depth + 1).tap { it.instance_exec(&block) if block }
        @entries << Entry.new(kind: :group, label:, id:, priority:, description:, icon:, children: child.entries)
      end

      def resource(key, label: nil, priority: nil, description: nil, icon: nil)
        @entries << Entry.new(kind: :resource, key: key.to_s, label:, priority:, description:, icon:)
      end

      def resources(*keys) = keys.each { resource(it) }

      def page(key, label: nil, priority: nil, description: nil, icon: nil)
        @entries << Entry.new(kind: :page, key: key.to_s, label:, priority:, description:, icon:)
      end

      # Resources and pages intentionally left out of the React menu: not placed, not reported as unplaced.
      def hide(*keys) = keys.each { @entries << Entry.new(kind: :hide, key: it.to_s) }

      # `if:` and a proc `url:` run in the view like AA's menu options, so `authorized?` and
      # `current_active_admin_user` are available.
      def link(label, url:, priority: nil, description: nil, icon: nil, id: nil, method: nil, if: nil)
        @entries << Entry.new(kind: :link, label:, url:, id:, priority:, description:, icon:, verb: method, display_if: binding.local_variable_get(:if))
      end
    end

    class << self
      def define(&block)
        @entries = [*entries, *Builder.new(1).tap { it.instance_exec(&block) }.entries]
        @version = version + 1
      end

      def entries = @entries ||= []

      def declared? = entries.any?

      def reset!
        @entries = []
        @version = version + 1
        @audit = nil
      end

      def version = @version ||= 0

      # Depth beyond what the client lays out is a mistake worth failing on early.
      def check_depth!(depth, what)
        return if depth <= MAX_DEPTH

        message = "reactiveadmin menu: #{what} is nested #{depth} levels deep; the maximum is #{MAX_DEPTH}"
        raise DepthError, message if Rails.env.local?

        Rails.logger.warn(message)
        ReactiveAdmin.diagnostics.record(:menu_too_deep, item: what.to_s, depth:)
      end

      # Explicit `link` entries: the labels leading to each and the id its menu node gets.
      def links(list = entries, path = [])
        list.flat_map do |entry|
          case entry.kind
          when :group then links(entry.children, [*path, entry.label])
          when :link then [{id: link_id(entry, path), path: [*path, entry.label], url: (entry.url if entry.url.is_a?(String))}]
          else []
          end
        end
      end

      def link_id(entry, path) = entry.id || [*path.map { slug(it) }, slug(entry.label)].join("/")

      def slug(value) = value.to_s.downcase.tr(" ", "_")

      def keys(kind, list = entries)
        list.flat_map { (it.kind == :group) ? keys(kind, it.children) : (it.key if it.kind == kind) }.compact
      end

      # Mismatches between the overlay and what is registered; resource keys only, never data.
      def audit
        stamp = [version, Registry.index.object_id]
        return @audit[:entries] if @audit && @audit[:stamp] == stamp

        found = compute_audit
        @audit = {stamp:, entries: found}
        found
      end

      def record_audit = audit.each { ReactiveAdmin.diagnostics.record(it[:kind], **it.except(:kind)) }

      # Whether the overlay can give the config a top-level entry: a resource needs an index, and one that
      # only exists under its parent has no top-level URL (AA lists it in the parent's own menu).
      def placeable?(config)
        (AA.in_menu?(config) || !Paths.nested?(config)) && (AA.page?(config) || Registry.actions(config).include?(:index))
      end

      private

      def compute_audit
        return [] unless declared?

        resources = keys(:resource)
        pages = keys(:page)
        hidden = keys(:hide)
        placed_resources = resources + hidden + Registry.resources.filter_map { Registry.route_key(it) if it.reactive_options[:menu]&.key?(:path) }
        registered = [*Registry.resources.map { Registry.route_key(it) }, *menu_pages.map { Menu.page_key(it) }]
        [
          *(hidden - registered).uniq.map { {kind: :menu_unknown, item: "hide", key: it} },
          *duplicates(:resource, resources), *duplicates(:page, pages),
          *unknown(:resource, resources, Registry.resources.to_h { [Registry.route_key(it), it] }),
          *unknown(:page, pages, menu_pages.to_h { [Menu.page_key(it), it] }),
          *unplaced(:resource, Registry.resources.select { Registry.actions(it).include?(:index) }.to_h { [Registry.route_key(it), it] }, placed_resources),
          *unplaced(:page, menu_pages.to_h { [Menu.page_key(it), it] }, pages + hidden)
        ]
      end

      def menu_pages = Registry.pages

      def duplicates(kind, keys) = keys.tally.select { |_, n| n > 1 }.keys.map { {kind: :menu_duplicate, item: kind.to_s, key: it} }

      def unknown(kind, keys, registered)
        keys.uniq.filter_map do |key|
          config = registered[key]
          if config.nil?
            {kind: :menu_unknown, item: kind.to_s, key:}
          elsif !placeable?(config) || !Exposure.allowed?(config)
            {kind: :menu_hidden, item: kind.to_s, key:}
          end
        end
      end

      def unplaced(kind, registered, placed)
        registered.filter_map { |key, config| {kind: :menu_unplaced, item: kind.to_s, key:} if AA.in_menu?(config) && !placed.include?(key) }
      end
    end

    # Rearranges evaluated menu nodes (hashes with :children) per the per-resource hints and the
    # overlay. Nodes are moved, never copied, so each resource appears once.
    class Layout
      def initialize(roots, evaluate:, build:)
        @roots = roots
        @evaluate = evaluate
        @build = build
        @overlay_placed = Set.new
      end

      def call
        place_declared_resources
        place(@roots, MenuOverlay.entries, [])
        MenuOverlay.keys(:hide).each { take(:resource, it) || take(:page, it) }
        @roots
      end

      private

      def place_declared_resources
        Registry.resources.each do |config|
          hint = config.reactive_options[:menu] or next
          key = Registry.route_key(config)
          node = hint.key?(:path) ? take(:resource, key) : find(@roots, :resource, key)&.first
          next unless node

          style(node, hint)
          attach(group_for(hint[:path]), node) if hint.key?(:path)
        end
      end

      def place(container, entries, path)
        entries.each_with_index do |entry, seq|
          case entry.kind
          when :group
            group = find_or_create_group(container, entry, path)
            group[:seq] = seq
            style(group, entry.to_h)
            place(group[:children], entry.children, [*path, entry.label])
          when :resource, :page
            next unless @overlay_placed.add?([entry.kind, entry.key])

            node = take(entry.kind, entry.key) || build_hidden(entry.kind, entry.key) or next
            attach(container, style(node.merge!(priority: DEFAULT_PRIORITY, seq:), entry.to_h))
          when :link
            next unless entry.display_if.nil? || @evaluate.call(entry.display_if)

            node = link_node(entry, path, seq)
            drop_inherited_link(node[:id])
            attach(container, node)
          end
        end
      end

      # A host-declared link replaces the AA menu item it redeclares, so it isn't listed twice.
      def drop_inherited_link(id, nodes = @roots)
        nodes.reject! { it[:id] == id && it[:kind].to_s == "link" }
        nodes.each { drop_inherited_link(id, it[:children]) if it[:children] }
      end

      # A resource AA keeps out of its menu has no node to move; the overlay's placement is the decision to show it.
      def build_hidden(kind, key)
        config = (kind == :page) ? Registry.find_page(key) : Registry.find(key)
        return unless config && !AA.in_menu?(config) && MenuOverlay.placeable?(config)

        node = @build.call(config)
        node if node && (node[:resource] || node[:page])
      end

      def style(node, options)
        node[:label] = options[:label] if options[:label]
        node[:priority] = options[:priority] if options[:priority]
        node[:description] = options[:description] if options[:description]
        node[:icon] = options[:icon] if options[:icon]
        node
      end

      def attach(container, node) = container << node

      def link_node(entry, path, seq)
        {id: MenuOverlay.link_id(entry, path), label: entry.label, kind: "link",
         url: @evaluate.call(entry.url).to_s, method: entry.verb&.to_s, priority: entry.priority || DEFAULT_PRIORITY,
         description: entry.description, icon: entry.icon, seq:, children: []}.compact.merge(resource: nil)
      end

      def group_for(path, container = @roots, trail = [])
        path.to_a.each do |label|
          group = container.find { group?(it, label) } || new_group(container, label, trail)
          container = group[:children]
          trail += [label]
        end
        container
      end

      def find_or_create_group(container, entry, path)
        container.find { group?(it, entry.label) } || new_group(container, entry.label, path, id: entry.id)
      end

      def new_group(container, label, path, id: nil)
        {id: id || [*path.map { slug(it) }, slug(label)].join("/"), label:, kind: "group", priority: DEFAULT_PRIORITY, children: []}.tap { container << it }
      end

      def group?(node, label) = node[:kind] == "group" && slug(node[:label]) == slug(label)

      def slug(value) = MenuOverlay.slug(value)

      def find(nodes, kind, key)
        nodes.each do |node|
          return [node, nodes] if node[kind] == key
          found = find(node[:children], kind, key)
          return found if found
        end
        nil
      end

      def take(kind, key)
        node, siblings = find(@roots, kind, key)
        siblings&.delete(node)
        node
      end
    end
  end
end
