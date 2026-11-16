module ReactiveAdmin
  module Ui
    # Publishes `ui_switch` audit events. The switch itself is the client writing the `reactiveadmin_ui` cookie and
    # reloading, so the server only sees it on the next request: a signed marker cookie remembers which UI this user
    # last had in this browser, and a session request whose cookie disagrees with it is a switch. A browser with
    # neither cookie never chose and gets no marker.
    module Switch
      MARKER = "reactiveadmin_ui_seen".freeze

      private

      def process_action(*)
        super.tap { reactiveadmin_notice_ui_switch }
      end

      def reactiveadmin_notice_ui_switch
        return unless Ui.settings.enabled && !Auth.token_based?(request)

        choice = cookies[COOKIE]
        seen = cookies.signed[MARKER]
        return if choice.nil? && seen.nil?

        user_id = ReactiveAdmin.current_user(self)&.id&.to_s or return
        # The shell renders the new admin for `new` only.
        mode = (choice == "new") ? "new" : "classic"
        seen_user, seen_mode = seen
        return if seen_user == user_id && seen_mode == mode

        # Another user's marker says nothing about this one; a missing one means the classic default.
        from = (seen_user == user_id) ? seen_mode : ("classic" if seen.nil?)
        Audit.publish(:ui_switch, self, resource: nil, action: nil, from:, to: mode) if from && from != mode
        cookies.signed[MARKER] = {value: [user_id, mode], httponly: true, same_site: :lax, secure: request.ssl?, expires: 1.year}
      rescue => e
        Rails.logger.error("[reactiveadmin] ui switch audit failed: #{e.class}")
      end
    end
  end
end
