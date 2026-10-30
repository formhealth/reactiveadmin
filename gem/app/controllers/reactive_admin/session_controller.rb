module ReactiveAdmin
  # Current user and the CSRF token clients must send as X-CSRF-Token on writes.
  class SessionController < ApiController
    def show
      lookup_context.formats = [:html]
      user = ReactiveAdmin.current_user(self)
      render json: {user: {id: user.id.to_s, display_name: AA.display_name(view_context, user)}, csrf_token: form_authenticity_token, ui: Ui.payload(user)},
        content_type: "application/json"
    end
  end
end
