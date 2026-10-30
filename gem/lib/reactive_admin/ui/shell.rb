module ReactiveAdmin
  module Ui
    # Answers a browser's navigation to the admin with the client's page when its `reactiveadmin_ui=new` cookie asks
    # for it. It knows nothing of resources, users or authorization: the page is the same static document for
    # everyone, and the client then asks the API (which authorizes as ever) and sends the browser back to classic
    # when it can't show the URL. A cookie is the only way to choose: browsers can't add a header to a navigation.
    #
    # Everything else passes through: fetches and frames, writes, other formats, `?classic=1` and `?embed=1`,
    # URLs outside the admin namespace, and every request while no client build is installed.
    class Shell
      include ERB::Util

      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)
        shell?(request) ? respond(request) : @app.call(env)
      end

      private

      def shell?(request)
        Ui.settings.enabled && (request.get? || request.head?) && in_namespace?(request.path_info) &&
          request.cookies[COOKIE] == "new" && document?(request) && !escaped?(request) && Assets.ready?
      end

      # A path ending in a known format is a download or another format (`posts.csv`), never a page. Other dots belong
      # to the record id (`users/john.doe`).
      def in_namespace?(path)
        root = "/#{ReactiveAdmin.config.namespace}"
        (path == root || path.start_with?("#{root}/")) && !Mime::Type.lookup_by_extension(File.extname(path).delete_prefix("."))
      end

      # Browsers say what a request is for; without `Sec-Fetch-Dest` (older ones) a page load asks for html.
      def document?(request)
        dest = request.get_header("HTTP_SEC_FETCH_DEST")
        return dest == "document" if dest

        !request.xhr? && request.get_header("HTTP_ACCEPT").to_s.include?("text/html")
      end

      def escaped?(request)
        request.GET.values_at("classic", "embed").include?("1")
      rescue Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError
        true
      end

      def respond(request)
        body = page(Assets.tags, request.content_security_policy_nonce)
        headers = (ActionDispatch::Response.default_headers || {}).transform_keys(&:downcase).merge(
          "content-type" => "text/html; charset=utf-8", "cache-control" => "no-store", "content-length" => body.bytesize.to_s
        )
        [200, headers, [request.head? ? "" : body]]
      end

      def page(tags, nonce)
        config = {admin_path: "/#{ReactiveAdmin.config.namespace}", mount_path: ReactiveAdmin.config.mount_path}.to_json
        <<~HTML
          <!DOCTYPE html>
          <html lang="#{h(I18n.locale)}">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Admin</title>
            <meta name="reactiveadmin-config" content="#{h(config)}">
            #{tags.styles.map { %(<link rel="stylesheet" href="#{h(it)}">) }.join("\n  ")}
            #{tags.preloads.map { %(<link rel="modulepreload" href="#{h(it)}">) }.join("\n  ")}
            <script type="module" src="#{h(tags.script)}"#{%( nonce="#{h(nonce)}") if nonce}></script>
          </head>
          <body>
            <div id="root"></div>
            <noscript><p>The admin needs JavaScript. <a href="?classic=1">Open the classic admin</a>.</p></noscript>
          </body>
          </html>
        HTML
      end
    end
  end
end
