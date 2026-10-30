module ReactiveAdmin
  module OpenApi
    # The paths and tag of one `register_page`: the page itself and its page actions. The fields of a form
    # in the page's content come with the page response (`forms`); rendering the content here would read data.
    class PageDoc
      include Parts

      attr_reader :paths

      def self.tag_name(page) = "page:#{Menu.page_key(page)}"

      def initialize(context, page)
        @ctx = context
        @page = page
        @key = Menu.page_key(page)
        @label = page.name.to_s
        @nested = Paths.nested?(page)
        @paths = {}
      end

      def call
        read
        actions
        {tag: {name: self.class.tag_name(@page), "x-displayName": @label, description: "The #{@label} page and its page actions."}, paths:}
      end

      private

      def tags = [self.class.tag_name(@page)]

      def prefix
        return "/#{ReactiveAdmin.config.namespace}/" unless @nested

        parent = @page.belongs_to_config
        "/#{ReactiveAdmin.config.namespace}/#{Registry.route_key(parent.target)}/{#{parent.to_param}}/"
      end

      def parameters = (@nested ? [path_param(@page.belongs_to_config.to_param.to_s, "Id of the parent record")] : [])

      def add(path, verb, operation, names: nil) = ((@paths[path] ||= {})[verb] = names ? operation.merge(guard_extensions(@page, names)) : operation)

      def id(name) = @ctx.ids.claim(name)

      def read
        add(Paths.api("#{prefix}_pages/#{@key}"), "get", operation(
          id: id("get#{camel(@key)}Page"), summary: "#{@label} page", tags:, parameters: [*parameters, *([form_query_param] if Ladder.page(@page).get_form)],
          description: "The page's content as typed nodes, its action items and the GET page actions that render something.",
          responses: {200 => success("The page", schema_ref("PageResponse"), degraded: true)}, errors: [403, 404]
        ), names: %w[index])
      end

      def actions
        @page.page_actions.sort_by { it.name.to_s }.each do |declaration|
          name = declaration.name.to_s
          next unless @ctx.authorized?(name.to_sym, @page, @page)

          verbs = verbs_of(declaration)
          verbs.each { action(name, it, suffix: (camel(it) if verbs.size > 1)) unless ApiGuards.denies?(@page, name, verb: it) }
        end
      end

      def action(name, verb, suffix:)
        get = verb == "get"
        add(Paths.api("#{prefix}#{@key}/#{name}"), verb, operation(
          id: id("#{camel(@key).camelize(:lower)}#{camel(name)}#{suffix}"), summary: "#{name.humanize} (page action)", tags:, write: !get,
          parameters: [*parameters, *([form_query_param] if get && Ladder.action(@page, name)&.get_form)],
          description: get ? "Answers the action's template as a form." : "Page action `#{name}`, usually the target of a form in the page's content. The redirect and flash become the result; an alert answers 422.",
          request_body: (ref("requestBodies", "ActionParams") unless get),
          responses: {200 => get ? shared("FormOk") : ref("responses", "ActionResult")},
          errors: [403, *(422 unless get)]
        ), names: [name])
      end
    end
  end
end
