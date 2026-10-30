class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  helper_method :current_admin_user

  def current_admin_user = (@current_admin_user ||= AdminUser.find_by(id: session[:admin_user_id]))

  def authenticate_admin_user!
    redirect_to "/login" unless current_admin_user
  end

  def handle_unauthorized_access(exception)
    flash[:alert] = "Access denied: #{exception.action} on #{exception.subject.class}"
    redirect_back fallback_location: "/admin"
  end
end
