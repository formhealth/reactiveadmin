module ReactiveAdmin
  # Bounds what one index or export request can cost and reveal. ActiveAdmin accepts any `per_page`
  # and sorts by any column, so on the API `per_page` is capped, `order` only names columns the
  # index shows, and exports have a row ceiling.
  module QueryGuard
    MAX_KEY_LENGTH = 100

    module_function

    # Page sizes the resource offers (`per_page: [25, 250]`) may be served even above the host cap.
    # A resource that turned pagination off keeps its own `max_per_page`: that is the page it asked for.
    def per_page_cap(config, offered = [])
      return config.max_per_page unless config.paginate

      host_cap = [ReactiveAdmin.config.max_per_page, *offered].compact.max
      [config.max_per_page, host_cap || config.max_per_page].min
    end

    # Clamps rather than rejects: a client asking for more gets the most it may have.
    def per_page(config, requested, fallback, offered = [])
      size = requested.to_s.match?(/\A\d+\z/) ? requested.to_i : fallback.to_i
      size = fallback.to_i unless size.positive?
      [size, per_page_cap(config, offered)].min
    end

    # The sort key of `order` when the index doesn't offer it, or nil. `sort_keys` come from the
    # displayed sortable columns; the resource's own default order is always allowed.
    def order_violation(config, order, sort_keys)
      return if order.blank? || order.to_s == config.sort_order.to_s

      clause = AA.order_clause(config, order.to_s)
      return if clause.valid? && sort_keys.include?(clause.field)

      (clause.valid? ? clause.field : order.to_s).truncate(MAX_KEY_LENGTH)
    end

    # Rows up to one past `limit`: a cheap probe, since an export streams and can't be refused once
    # it started.
    def count_rows(collection, limit)
      rows = collection.except(:order).limit(limit + 1).count(:all)
      rows.is_a?(Hash) ? rows.size : rows
    end

    module Guard
      # Exports are AA's own streaming, so the order and size checks run before it starts.
      def index(*)
        return super unless reactiveadmin_export?

        super if export_allowed?
      end

      protected

      def per_page
        return super unless reactiveadmin_request?

        QueryGuard.per_page(active_admin_config, super, configured_per_page, offered_per_page)
      end

      private

      def offered_per_page
        view = IndexViews.new(active_admin_config, as: params[:as]).per_page_options
        [*view, *(active_admin_config.per_page if active_admin_config.per_page.is_a?(Array))].grep(Integer)
      end

      def export_allowed?
        sort = IndexPayload.new(self).unsupported_sort
        raise ApiErrors::BadRequest, "Unsupported sort: #{sort}" if sort

        limit = ReactiveAdmin.config.max_export_rows
        rows = QueryGuard.count_rows(AA.collection(self), limit) if limit
        if limit && rows > limit
          render_api_error(:invalid, "Narrow your filters to export fewer than #{limit} rows", 422)
          return false
        end

        ActiveSupport::Notifications.instrument("export.reactiveadmin", resource: Registry.route_key(active_admin_config),
          user_id: ReactiveAdmin.current_user(self)&.id, filters: params[:q].try(:keys).to_a.map(&:to_s), scope: AA.current_scope(self)&.id, row_count: rows)
        true
      end
    end
  end
end
