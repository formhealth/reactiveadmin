module ReactiveAdmin
  # The AA namespace's settings (title, logout, formats, ...) evaluated for the current user.
  class Site
    def initialize(controller, menu)
      @view = controller.view_context
      @user = ReactiveAdmin.current_user(controller)
      @menu = menu
      @settings = AA.site_settings(Registry.namespace, @view)
      @host = controller.request.host
    end

    def as_json(*)
      {
        title: @settings[:title].to_s,
        title_link: @settings[:title_link].presence,
        title_image: asset(@settings[:title_image]),
        favicon: asset(@settings[:favicon]),
        home:,
        logout:,
        utility_menu: @menu.menu(AA.utility_menu),
        current_user: current_user,
        locale: I18n.locale.to_s,
        time_zone: @user.try(:time_zone).presence || Time.zone.name,
        date_format: I18n.t("date.formats.#{localize_format}", default: nil),
        datetime_format: I18n.t("time.formats.#{localize_format}", default: nil),
        footer: @settings[:footer].presence,
        comments: @settings[:comments],
        default_per_page: @settings[:default_per_page],
        max_per_page: @settings[:max_per_page],
        trusted_media_hosts: HtmlPolicy.trusted_hosts
      }
    end

    private

    def current_user = @user && {id: @user.id.to_s, display_name: Values.display_label(@user, @view)}

    def localize_format = AA.localize_format

    def asset(path) = (@view.asset_path(path) if path.present?)

    def home
      url = @view.public_send(:"#{@settings[:name]}_root_path")
      Location.for(url, host: @host).slice(:resource, :url)
    rescue NoMethodError
      nil
    end

    def logout
      return unless (path = @settings[:logout_path])

      {url: AA.render_or_call(@view, @view, path), method: (@settings[:logout_method] || :get).to_s.downcase}
    end
  end
end
