module ReactiveAdmin
  module Mcp
    module Tools
      # Asks the index for one row and reads the page meta, so authorization, scoping, the declared-filter
      # allowlist and the ransack guard are the index's own. The row is dropped: only counts are returned.
      define :count_records, title: "Count records",
        description: "How many records match, without reading them: the total for the filters and scope, and the count per scope. Use it before list_records to size a query, or to answer how-many questions. filters and scope work as in list_records.",
        properties: {resource: RESOURCE, parent_id: PARENT, filters: {type: "object", description: "Declared filter params to values."},
                     scope: {type: "string", description: "Scope id from describe_resource."}}, required: [:resource] do |ctx, args|
        filters = args.fetch("filters", {})
        bad = filters.keys.grep_v(FILTER_NAME)
        raise ToolError, "Invalid filter name #{bad.first.to_s.first(40).inspect}." if bad.any?

        meta = ctx.api.get!(ctx.collection_path(args), {q: filters.presence, scope: args["scope"], per_page: 1})["meta"]
        scopes = meta["scopes"].map { it.slice("id", "name", "count").compact }.presence
        total = meta["total_count"]
        {resource: args["resource"], total:, scope: meta["current_scope"], scopes:,
         note: ("This resource doesn't count totals, so none is available." if total.nil?)}.compact
      end
    end
  end
end
