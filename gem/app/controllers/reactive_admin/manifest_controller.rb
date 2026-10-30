module ReactiveAdmin
  class ManifestController < ApiController
    before_action :authorize_root!

    def show
      lookup_context.formats = [:html]
      render json: Manifest.new(self).as_json, content_type: "application/json"
    end
  end
end
