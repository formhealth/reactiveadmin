ActiveAdmin.register Ticket do
  menu false

  permit_params :title

  reactive do
    expose :retitle
    expose :broken
    expose :plain
    expose :lookup
    expose :related
    expose :elsewhere
    own_query_params :find
  end

  member_action :related, method: :get do
    @search = TicketSearch.new(params.fetch(:filter, {}).permit(:term, :pick))
  end

  member_action :elsewhere, method: :get do
    @search = TicketSearch.new
  end

  member_action :find, method: :get do
    render json: {term: params.dig(:q, :term)}
  end

  member_action :retitle, method: [:get, :put] do
    resource.update!(title: params[:title]) if request.put?
  end

  member_action :broken, method: :get

  member_action :plain, method: [:get, :put] do
    render plain: params.permit(:title, labels: []).to_h.to_json if request.put?
  end

  member_action :lookup, method: [:get, :post] do
    @search = TicketSearch.new(params.fetch(:q, {}).permit(:term))
    flash.now[:alert] = "Lookup is down" if @search.term == "down"
    render :lookup
  end

  member_action :close, method: :post do
    resource.update!(title: "#{resource.title} (closed)")
    redirect_to lookup_admin_ticket_path(resource), notice: "Closed"
  end

  member_action :escalate, method: :post do
    redirect_to lookup_admin_ticket_path(resource), alert: "Cannot escalate"
  end
end
