module ReactiveAdmin
  module Ui
    # View helper for the classic admin: `text_node reactiveadmin_ui_toggle` on an ActiveAdmin page (the
    # dashboard), or `<%= reactiveadmin_ui_toggle %>` in a partial. Renders nothing for users who can't switch,
    # inside the client's frames, or while no client build is installed. The build's `uiToggle` script sets the
    # cookie, and applies `ui.default` to a browser that has none.
    module Helper
      def reactiveadmin_ui_toggle
        user = ReactiveAdmin.current_user(controller)
        script = Ui::Assets.toggle_script
        return "".html_safe unless script && params[:embed] != "1" && Ui.available?(user)

        returning = params[:classic] == "1"
        tag.div(class: "panel reactiveadmin-ui-toggle", data: {reactiveadmin_ui: Ui.default_mode(user)}) do
          tag.h3(returning ? "The new admin" : "Try the new admin") +
            tag.div(class: "panel_contents") do
              tag.p(returning ? "You're viewing a classic page on request." : "The same pages in a faster, redesigned admin. You can switch back at any time.") +
                tag.button(returning ? "Return to the new admin" : "Try the new admin", type: "button", data: {reactiveadmin_ui_mode: "new"})
            end
        end + tag.script(src: script, type: "module", nonce: content_security_policy_nonce)
      end
    end
  end
end
