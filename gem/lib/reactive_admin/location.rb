module ReactiveAdmin
  # Where a redirect points, as a resource reference when it lands on one of our resources.
  module Location
    VIEWS = %w[index show new edit].freeze

    module_function

    def for(url, host:)
      uri = URI.parse(url.to_s)
      return {url: url.to_s} if uri.host.present? && uri.host != host

      location = {url: [uri.path, uri.query].compact.join("?")}
      route = Rails.application.routes.recognize_path(uri.path)
      config = Registry.for_controller_path(route[:controller])
      return location unless config && VIEWS.include?(route[:action]) && Exposure.allowed?(config)

      location.merge(resource: Registry.route_key(config), id: route[:id]&.to_s, view: route[:action]).compact
    rescue URI::InvalidURIError, ActionController::RoutingError
      {url: url.to_s}
    end
  end
end
