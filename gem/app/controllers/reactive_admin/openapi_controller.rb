module ReactiveAdmin
  # The OpenAPI document of what the signed-in user may do. Plain JSON, so any docs viewer can fetch it.
  class OpenapiController < ApiController
    include RateLimit::Guard

    before_action :authorize_root!

    def show
      lookup_context.formats = [:html]
      render json: OpenApi.fetch(self), content_type: "application/json"
    end
  end
end
