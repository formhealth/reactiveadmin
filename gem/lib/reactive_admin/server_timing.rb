module ReactiveAdmin
  # Adds a Server-Timing header (total app time and time spent in SQL) to API responses.
  class ServerTiming
    KEY = :reactiveadmin_db_ms
    STATE = ActiveSupport::IsolatedExecutionState

    # One global subscriber that only counts while a request has opened a counter on its own
    # thread/fiber, so concurrent requests don't see each other's queries.
    ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
      STATE[KEY] += event.duration if STATE[KEY] && event.payload[:name] != "SCHEMA"
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless env["PATH_INFO"].start_with?("#{ReactiveAdmin.config.mount_path}/")

      outer = STATE[KEY]
      STATE[KEY] = 0.0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status, headers, body = @app.call(env)
      app_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      headers["Server-Timing"] = format("db;dur=%.1f, app;dur=%.1f", STATE[KEY], app_ms)
      [status, headers, body]
    ensure
      STATE[KEY] = outer
    end
  end
end
