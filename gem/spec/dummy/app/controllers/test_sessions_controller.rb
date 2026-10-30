class TestSessionsController < ApplicationController
  skip_forgery_protection

  def new = head(:unauthorized)

  def create
    session[:admin_user_id] = params[:id]
    head :no_content
  end

  def destroy
    reset_session
    head :no_content
  end
end
