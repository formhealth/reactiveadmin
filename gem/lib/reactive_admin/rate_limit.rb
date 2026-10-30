module ReactiveAdmin
  # Per-user request budgets for the endpoints that are cheap to call and expensive to serve.
  # Fixed windows on `Rails.cache` (atomic `increment`), keyed by user and bucket and never by IP,
  # which is shared behind a VPN or proxy. A store that can't count (the null store) or fails
  # leaves requests unlimited rather than locking operators out.
  module RateLimit
    BUCKETS = {"reactiveadmin_options" => :options, "reactiveadmin_lookup" => :lookup, "reactiveadmin_value" => :value}.freeze

    module_function

    # Seconds until the user may retry when the request is over budget, otherwise nil.
    def retry_after(bucket, user_id, now: Time.now.to_i)
      limit, period = limit_for(bucket)
      return unless limit && user_id

      window = period.to_i
      count = Rails.cache.increment("reactiveadmin:rl:#{bucket}:#{user_id}:#{now / window}", 1, expires_in: window + 1)
      window - (now % window) if count.to_i > limit
    rescue => e
      Rails.logger.warn("[reactiveadmin] rate limit unavailable: #{e.class}")
      nil
    end

    def limit_for(bucket)
      limits = ReactiveAdmin.config.rate_limits
      return unless limits

      limits.fetch(bucket) { limits[:default] }
    end

    def bucket(controller)
      return :export if controller.send(:reactiveadmin_export?)
      return :options if controller.params[:context] == "page_form"

      BUCKETS.fetch(controller.action_name, :default)
    end

    # Prepended after authentication so the budget belongs to a known user, before any query runs.
    module Guard
      private

      def authenticate_active_admin_user
        super
        throttle_reactiveadmin_request unless performed? || !reactiveadmin_request?
      end

      # The doctor's samples are set server-side, so they must not drain the operator's budget.
      def throttle_reactiveadmin_request
        return if request.env[BackgroundRequests::INTERNAL_ENV]

        seconds = RateLimit.retry_after(RateLimit.bucket(self), ReactiveAdmin.current_user(self)&.id)
        return unless seconds

        response.headers["Retry-After"] = seconds.to_s
        render_api_error(:rate_limited, "Too many requests; try again in #{seconds} seconds", 429)
      end
    end
  end
end
